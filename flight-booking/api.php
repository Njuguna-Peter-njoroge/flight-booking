<?php
header('Content-Type: application/json');
require_once 'db.php';

session_set_cookie_params([
    'httponly' => true,
    'samesite' => 'Lax',
    'secure'   => !empty($_SERVER['HTTPS']),
]);
session_start();

// Sign out after 2 hours of inactivity
if (isset($_SESSION['last']) && time() - $_SESSION['last'] > 7200) { $_SESSION = []; }
$_SESSION['last'] = time();

$action = $_GET['action'] ?? '';

function fail(string $msg, int $code = 400): void {
    http_response_code($code);
    echo json_encode(['error' => $msg]);
    exit;
}

function body(): array {
    $d = json_decode(file_get_contents('php://input'), true);
    return is_array($d) ? $d : [];
}

// Allow 5 wrong sign-ins per 10 minutes per browser session
function throttled(): bool {
    $_SESSION['fails'] = array_values(array_filter($_SESSION['fails'] ?? [], fn($t) => $t > time() - 600));
    return count($_SESSION['fails']) >= 5;
}
function note_fail(): void { $_SESSION['fails'][] = time(); }

function member_name(PDO $pdo, int $uid): string {
    $st = $pdo->prepare("SELECT p.first_name, p.last_name, u.email FROM users u
                         LEFT JOIN passengers p ON p.user_id = u.user_id WHERE u.user_id = ?");
    $st->execute([$uid]);
    $r = $st->fetch();
    if (!$r) return 'Member';
    return $r['first_name'] ? $r['first_name'] . ' ' . $r['last_name'] : $r['email'];
}

function crew_name(PDO $pdo, int $cid): string {
    $st = $pdo->prepare("SELECT first_name, last_name, staff_role FROM crew_members WHERE crew_id = ?");
    $st->execute([$cid]);
    $c = $st->fetch();
    if (!$c) return 'Crew';
    return ucwords(str_replace('_', ' ', $c['staff_role'])) . " {$c['first_name']} {$c['last_name']}";
}

try {
    switch ($action) {

        // ---------- AUTH ----------
        case 'login_member':
            $d     = body();
            $email = trim($d['email'] ?? '');
            $pw    = (string)($d['password'] ?? '');

            if (throttled()) fail('Too many attempts. Please wait a few minutes and try again.', 429);

            $stmt = $pdo->prepare("SELECT user_id, password_hash FROM users WHERE email = ?");
            $stmt->execute([$email]);
            $u = $stmt->fetch();

            $ok = false;
            if ($u) {
                if (password_verify($pw, $u['password_hash'])) {
                    $ok = true;
                } elseif (hash_equals($u['password_hash'], hash('sha256', $pw))) {
                    // Old SHA2 hash from the seed data: accept once, then upgrade it
                    $ok = true;
                    $pdo->prepare("UPDATE users SET password_hash = ? WHERE user_id = ?")
                        ->execute([password_hash($pw, PASSWORD_DEFAULT), $u['user_id']]);
                }
            }
            if (!$ok) { note_fail(); fail('Incorrect email or password.', 401); }

            session_regenerate_id(true);
            $_SESSION = ['user_id' => (int)$u['user_id']];
            echo json_encode(['success' => true, 'name' => member_name($pdo, (int)$u['user_id'])]);
            break;

        case 'login_crew':
            $d    = body();
            $code = trim($d['code'] ?? '');
            if (throttled()) fail('Too many attempts. Please wait a few minutes and try again.', 429);

            $stmt = $pdo->prepare("SELECT crew_id, first_name, last_name, staff_role
                                   FROM crew_members WHERE passport_number = ?");
            $stmt->execute([$code]);
            $c = $stmt->fetch();
            if (!$c) { note_fail(); fail('Staff ID not recognised.', 401); }

            session_regenerate_id(true);
            $_SESSION = ['crew_id' => (int)$c['crew_id']];
            $role = ucwords(str_replace('_', ' ', $c['staff_role']));
            echo json_encode(['success' => true, 'name' => "$role {$c['first_name']} {$c['last_name']}"]);
            break;

        case 'register':
            if (throttled()) fail('Too many attempts. Please wait a few minutes and try again.', 429);
            $d        = body();
            $first    = trim($d['first_name'] ?? '');
            $last     = trim($d['last_name'] ?? '');
            $email    = strtolower(trim($d['email'] ?? ''));
            $phone    = trim($d['phone'] ?? '');
            $passport = strtoupper(trim($d['passport_number'] ?? ''));
            $dob      = trim($d['date_of_birth'] ?? '');
            $pw       = (string)($d['password'] ?? '');

            if ($first === '' || $last === '' || mb_strlen($first) > 50 || mb_strlen($last) > 50) fail('Please enter your first and last name.');
            if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 150) fail('Please enter a valid email address.');
            if ($phone !== '' && !preg_match('/^\+?[0-9 ()-]{7,20}$/', $phone)) fail('Please enter a valid phone number, or leave it empty.');
            if (!preg_match('/^[A-Z0-9-]{5,20}$/', $passport)) fail('Passport number must be 5 to 20 letters or digits.');
            $dt = DateTime::createFromFormat('Y-m-d', $dob);
            if (!$dt || $dt->format('Y-m-d') !== $dob || $dt > new DateTime('today') || $dt < new DateTime('1900-01-01')) fail('Please enter a valid date of birth.');
            if (strlen($pw) < 8) fail('Password must be at least 8 characters.');

            try {
                $pdo->beginTransaction();
                $pdo->prepare("INSERT INTO users (email, password_hash, phone_number) VALUES (?, ?, ?)")
                    ->execute([$email, password_hash($pw, PASSWORD_DEFAULT), $phone]);
                $uid = (int)$pdo->lastInsertId();
                $pdo->prepare("INSERT INTO passengers (first_name, last_name, passport_number, date_of_birth, user_id)
                               VALUES (?, ?, ?, ?, ?)")
                    ->execute([$first, $last, $passport, $dob, $uid]);
                $pdo->commit();
            } catch (PDOException $e) {
                if ($pdo->inTransaction()) { $pdo->rollBack(); }
                if ($e->getCode() === '23000') {
                    note_fail();
                    fail('An account with that email or passport number already exists.', 409);
                }
                throw $e;
            }

            // Sign the new member straight in
            session_regenerate_id(true);
            $_SESSION = ['user_id' => $uid];
            echo json_encode(['success' => true, 'name' => "$first $last"]);
            break;

        // Who is signed in? (used to restore the session on page load)
        case 'me':
            if (!empty($_SESSION['user_id'])) {
                echo json_encode(['role' => 'member', 'name' => member_name($pdo, (int)$_SESSION['user_id'])]);
            } elseif (!empty($_SESSION['crew_id'])) {
                echo json_encode(['role' => 'crew', 'name' => crew_name($pdo, (int)$_SESSION['crew_id'])]);
            } else {
                echo json_encode(['role' => null]);
            }
            break;

        case 'logout':
            if ($_SERVER['REQUEST_METHOD'] !== 'POST') fail('Use POST to sign out.', 405);
            $_SESSION = [];
            if (ini_get('session.use_cookies')) {
                $cp = session_get_cookie_params();
                setcookie(session_name(), '', time() - 42000, $cp['path'], $cp['domain'], $cp['secure'], $cp['httponly']);
            }
            session_destroy();
            echo json_encode(['success' => true]);
            break;

        // ---------- PUBLIC DATA ----------
        case 'get_flights':
            // Only upcoming flights that can still be booked
            $stmt = $pdo->query("SELECT f.flight_id, f.flight_number, f.departure_airport, f.arrival_airport,
                                        f.departure_time, f.arrival_time, f.status, f.base_price,
                                        dep.city AS dep_city, arr.city AS arr_city
                                 FROM flights f
                                 JOIN airports dep ON f.departure_airport = dep.airport_code
                                 JOIN airports arr ON f.arrival_airport = arr.airport_code
                                 WHERE f.status IN ('scheduled','delayed') AND f.departure_time > NOW()
                                 ORDER BY f.departure_time");
            echo json_encode($stmt->fetchAll());
            break;

        case 'get_available_seats':
            $flight_id = (int)($_GET['flight_id'] ?? 0);
            $stmt = $pdo->prepare("SELECT * FROM view_available_seats WHERE flight_id = ?");
            $stmt->execute([$flight_id]);
            echo json_encode($stmt->fetchAll());
            break;

        // Every seat on the flight's aircraft, with a taken flag (used by the cabin map)
        case 'get_seats':
            $flight_id = (int)($_GET['flight_id'] ?? 0);
            $stmt = $pdo->prepare("SELECT s.seat_id, s.seat_number, s.cabin_class,
                                          (t.ticket_id IS NOT NULL) AS taken
                                   FROM flights f
                                   JOIN seats s ON s.aircraft_id = f.aircraft_id
                                   LEFT JOIN tickets t ON t.flight_id = f.flight_id AND t.seat_id = s.seat_id
                                   WHERE f.flight_id = ?
                                   ORDER BY s.seat_id");
            $stmt->execute([$flight_id]);
            echo json_encode($stmt->fetchAll());
            break;

        // ---------- MEMBER ----------
        case 'book_seat':
            if (empty($_SESSION['user_id'])) fail('Please sign in to book a seat.', 401);

            $d         = body();
            $flight_id = (int)($d['flight_id'] ?? 0);
            $seat_id   = (int)($d['seat_id'] ?? 0);
            if (!$flight_id || !$seat_id) fail('Missing booking details.');

            // Passenger profile linked to the signed-in account
            $stmt = $pdo->prepare("SELECT passenger_id FROM passengers WHERE user_id = ? LIMIT 1");
            $stmt->execute([$_SESSION['user_id']]);
            $passenger = $stmt->fetch();
            if (!$passenger) fail('No passenger profile is linked to this account.', 403);

            // The flight must be bookable and the seat must belong to its aircraft
            $stmt = $pdo->prepare("SELECT f.base_price,
                                          DATE_SUB(f.departure_time, INTERVAL 45 MINUTE) AS boarding_time
                                   FROM flights f
                                   JOIN seats s ON s.aircraft_id = f.aircraft_id
                                   WHERE f.flight_id = ? AND s.seat_id = ?
                                     AND f.status IN ('scheduled','delayed')
                                     AND f.departure_time > NOW()");
            $stmt->execute([$flight_id, $seat_id]);
            $flight = $stmt->fetch();
            if (!$flight) fail('That seat is not available on this flight.');

            // Unique 6-character booking reference
            $check = $pdo->prepare("SELECT 1 FROM bookings WHERE booking_reference = ?");
            do {
                $pnr = strtoupper(bin2hex(random_bytes(3)));
                $check->execute([$pnr]);
            } while ($check->fetch());

            $pdo->beginTransaction();

            $stmt1 = $pdo->prepare("INSERT INTO bookings
                (booking_reference, user_id, passenger_id, flight_id, price, payment_status)
                VALUES (?, ?, ?, ?, ?, 'pending')");
            $stmt1->execute([$pnr, $_SESSION['user_id'], $passenger['passenger_id'], $flight_id, $flight['base_price']]);
            $booking_id = $pdo->lastInsertId();

            // unique_flight_seat makes a double booking fail here
            $stmt2 = $pdo->prepare("INSERT INTO tickets (booking_id, flight_id, seat_id, boarding_time)
                                    VALUES (?, ?, ?, ?)");
            $stmt2->execute([$booking_id, $flight_id, $seat_id, $flight['boarding_time']]);

            $pdo->commit();
            echo json_encode(['success' => true, 'pnr' => $pnr]);
            break;

        // ---------- CREW ----------
        case 'get_pilot_roster':
            if (empty($_SESSION['crew_id'])) fail('Please sign in with your staff ID.', 401);

            $stmt = $pdo->prepare("SELECT f.flight_number, f.departure_airport, f.arrival_airport,
                                          f.departure_time, f.status
                                   FROM flight_crew fc
                                   JOIN flights f ON fc.flight_id = f.flight_id
                                   WHERE fc.crew_id = ?
                                   ORDER BY f.departure_time");
            $stmt->execute([$_SESSION['crew_id']]);
            echo json_encode($stmt->fetchAll());
            break;

        default:
            fail('Unknown action.');
    }
} catch (PDOException $e) {
    if ($pdo->inTransaction()) { $pdo->rollBack(); }
    if ($e->getCode() === '23000') {
        fail('That seat has just been booked. Please choose another.', 409);
    }
    error_log($e->getMessage());
    fail('Something went wrong. Please try again.', 500);
} catch (Exception $e) {
    if ($pdo->inTransaction()) { $pdo->rollBack(); }
    error_log($e->getMessage());
    fail('Something went wrong. Please try again.', 500);
}