-- =====================================================================
--  flight_booking_db  -  full setup script (run top to bottom, once)
--
--  Build plan (each step only depends on steps above it):
--    1. Database
--    2. Tables with no dependencies : airports, aircrafts, users
--    3. Tables that depend on those  : seats, flights, passengers
--    4. Tables that depend on 3      : bookings, tickets, crew_members,
--                                      flight_crew, baggage, loyalty_programs
--    5. View                         : view_available_seats
--    6. Data, inserted in the same order the tables were created
--    7. Checks
--
--  To rebuild from scratch, un-comment the DROP line below first.
--  This script contains the same tables, columns and data as before;
--  the later ALTER TABLE changes are now part of the CREATE TABLE
--  statements (flights.aircraft_id, flights.base_price,
--  bookings.user_id, passengers.user_id).
-- =====================================================================



-- =====================================================================
--  2. INDEPENDENT TABLES
-- =====================================================================

-- Airports where a plane can take off and land
CREATE TABLE airports (
    airport_code char(3) PRIMARY KEY,
    airport_name varchar(100) NOT NULL,
    city         varchar(150) NOT NULL,
    country      varchar(50)  NOT NULL
);

-- Physical aircraft
CREATE TABLE aircrafts (
    aircraft_id    int AUTO_INCREMENT PRIMARY KEY,
    aircraft_model varchar(50) NOT NULL,
    total_seats    int NOT NULL
);

-- Account credentials
CREATE TABLE users (
    user_id       int AUTO_INCREMENT PRIMARY KEY,
    email         varchar(150) UNIQUE NOT NULL,
    password_hash varchar(255) NOT NULL,
    phone_number  varchar(20),
    created_at    timestamp DEFAULT CURRENT_TIMESTAMP
);


-- =====================================================================
--  3. FIRST-LEVEL DEPENDENT TABLES
-- =====================================================================

-- Seats that belong to an aircraft
CREATE TABLE seats (
    seat_id      int AUTO_INCREMENT PRIMARY KEY,
    aircraft_id  int NOT NULL,
    seat_number  varchar(10) NOT NULL,
    cabin_class  enum('economy','premium_economy','business','first-class') NOT NULL,
    FOREIGN KEY (aircraft_id) REFERENCES aircrafts (aircraft_id),
    UNIQUE KEY unique_aircraft_seat (aircraft_id, seat_number)
);

-- Flights link departure and arrival back to airports, and to an aircraft
CREATE TABLE flights (
    flight_id         int AUTO_INCREMENT PRIMARY KEY,
    flight_number     varchar(10) NOT NULL,
    aircraft_id       int,
    departure_airport char(3) NOT NULL,
    arrival_airport   char(3) NOT NULL,
    departure_time    datetime NOT NULL,
    arrival_time      datetime NOT NULL,
    status            enum('scheduled','delayed','departed','arrived','cancelled') NOT NULL DEFAULT 'scheduled',
    base_price        decimal(10,2) NOT NULL DEFAULT 450.00,
    FOREIGN KEY (departure_airport) REFERENCES airports (airport_code),
    FOREIGN KEY (arrival_airport)   REFERENCES airports (airport_code),
    CONSTRAINT fk_flight_ircraft FOREIGN KEY (aircraft_id) REFERENCES aircrafts (aircraft_id)
);

-- Passengers who can hold a ticket; user_id links them to a login (optional)
CREATE TABLE passengers (
    passenger_id    int AUTO_INCREMENT PRIMARY KEY,
    first_name      varchar(50) NOT NULL,
    last_name       varchar(50) NOT NULL,
    passport_number varchar(20) UNIQUE NOT NULL,
    date_of_birth   date NOT NULL,
    user_id         int NULL,
    CONSTRAINT fk_passenger_user FOREIGN KEY (user_id) REFERENCES users (user_id)
);


-- =====================================================================
--  4. SECOND-LEVEL DEPENDENT TABLES
-- =====================================================================

-- Bookings: who booked which flight
CREATE TABLE bookings (
    booking_id        int AUTO_INCREMENT PRIMARY KEY,
    user_id           int,
    booking_reference char(6) UNIQUE NOT NULL,
    passenger_id      int NOT NULL,
    flight_id         int NOT NULL,
    booking_date      timestamp DEFAULT CURRENT_TIMESTAMP,
    price             decimal(10,2) NOT NULL,
    payment_status    varchar(20) DEFAULT 'pending',
    FOREIGN KEY (passenger_id) REFERENCES passengers (passenger_id),
    FOREIGN KEY (flight_id)    REFERENCES flights (flight_id),
    CONSTRAINT fk_booking_user FOREIGN KEY (user_id) REFERENCES users (user_id)
);

-- Tickets: one seat per flight (unique_flight_seat blocks double booking)
CREATE TABLE tickets (
    ticket_id     int AUTO_INCREMENT PRIMARY KEY,
    booking_id    int NOT NULL,
    flight_id     int NOT NULL,
    seat_id       int NOT NULL,
    boarding_time datetime,
    FOREIGN KEY (booking_id) REFERENCES bookings (booking_id),
    FOREIGN KEY (flight_id)  REFERENCES flights (flight_id),
    FOREIGN KEY (seat_id)    REFERENCES seats (seat_id),
    UNIQUE KEY unique_flight_seat (flight_id, seat_id),
    UNIQUE KEY unique_bookng_passenger (booking_id, seat_id)
);

-- Crew
CREATE TABLE crew_members (
    crew_id         int AUTO_INCREMENT PRIMARY KEY,
    first_name      varchar(50) NOT NULL,
    last_name       varchar(50) NOT NULL,
    staff_role      enum('captain','first_officer','purser','flight_attendant') NOT NULL,
    passport_number varchar(50) UNIQUE NOT NULL
);

CREATE TABLE flight_crew (
    flight_id int NOT NULL,
    crew_id   int NOT NULL,
    PRIMARY KEY (flight_id, crew_id),
    FOREIGN KEY (flight_id) REFERENCES flights (flight_id) ON DELETE CASCADE,
    FOREIGN KEY (crew_id)   REFERENCES crew_members (crew_id) ON DELETE CASCADE
);

-- Baggage checked in against a ticket
CREATE TABLE baggage (
    baggage_id       int AUTO_INCREMENT PRIMARY KEY,
    ticket_id        int NOT NULL,
    weight_kg        decimal(5,2) NOT NULL,
    tracking_barcode varchar(50) UNIQUE NOT NULL,
    baggage_status   enum('checked_in','tsa_cleared','loaded','in_transit','claimed','lost') DEFAULT 'checked_in',
    FOREIGN KEY (ticket_id) REFERENCES tickets (ticket_id) ON DELETE CASCADE
);

-- Frequent flyer accounts
CREATE TABLE loyalty_programs (
    loyalty_id        int AUTO_INCREMENT PRIMARY KEY,
    user_id           int NOT NULL,
    membership_number varchar(20) UNIQUE NOT NULL,
    miles_balance     int DEFAULT 0,
    tier_level        enum('bronze','silver','gold','platinum') DEFAULT 'bronze',
    FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE CASCADE
);






-- =====================================================================
--  6. DATA  (same order as the tables above)
-- =====================================================================

INSERT INTO airports (airport_code, airport_name, city, country) VALUES
('JFK', 'John F. Kennedy International Airport', 'New York', 'United States'),
('LHR', 'London Heathrow Airport', 'London', 'United Kingdom'),
('NBO', 'Jomo Kenyatta International Airport', 'Nairobi', 'Kenya');

INSERT INTO aircrafts (aircraft_model, total_seats) VALUES
('Boeing 737-800', 162);

INSERT INTO seats (aircraft_id, seat_number, cabin_class) VALUES
(1, '1A',  'business'),
(1, '1B',  'business'),
(1, '12A', 'economy'),
(1, '12B', 'economy'),
(1, '14A', 'economy'),
(1, '14B', 'economy');

-- All three flights use aircraft 1 so each has a seat map
INSERT INTO flights (flight_number, aircraft_id, departure_airport, arrival_airport, departure_time, arrival_time, status) VALUES
('KQ100', 1, 'NBO', 'LHR', '2026-11-15 08:30:00', '2026-11-15 15:45:00', 'scheduled'),
('AA204', 1, 'JFK', 'LHR', '2026-11-16 19:00:00', '2026-11-17 07:15:00', 'scheduled'),
('KQ502', 1, 'LHR', 'NBO', '2026-11-18 21:00:00', '2026-11-19 06:30:00', 'scheduled');

-- Logins (passwords are SHA2 here; api.php upgrades each one on first sign-in)
INSERT INTO users (email, password_hash, phone_number) VALUES
('alice.njeri@dreamCoder.com', SHA2('mysecurepassword123', 256), ''),
('brian.otieno@example.com',   SHA2('BrianPass2026!', 256),      '+254700000001'),
('grace.wanjiru@example.com',  SHA2('GracePass2026!', 256),      '+254700000002'),
('kevin.mwangi@example.com',   SHA2('KevinPass2026!', 256),      '+254700000003'),
('faith.achieng@example.com',  SHA2('FaithPass2026!', 256),      '+254700000004'),
('samuel.kiptoo@example.com',  SHA2('SamuelPass2026!', 256),     '+254700000005'),
('mercy.wambui@example.com',   SHA2('MercyPass2026!', 256),      '+254700000006'),
('peter.omondi@example.com',   SHA2('PeterPass2026!', 256),      '+254700000007'),
('lucy.chebet@example.com',    SHA2('LucyPass2026!', 256),       '+254700000008');

-- Passengers, each linked to their login by email (John has no login)
INSERT INTO passengers (first_name, last_name, passport_number, date_of_birth, user_id)
SELECT v.first_name, v.last_name, v.passport_number, v.dob, u.user_id
FROM (
    SELECT 'Alice' AS first_name, 'Njeri' AS last_name, 'A1234567B' AS passport_number, '1995-04-12' AS dob, 'alice.njeri@dreamCoder.com' AS email
    UNION ALL SELECT 'Brian',  'Otieno',  'B7654321C', '1992-08-03', 'brian.otieno@example.com'
    UNION ALL SELECT 'Grace',  'Wanjiru', 'G1122334D', '1990-02-17', 'grace.wanjiru@example.com'
    UNION ALL SELECT 'Kevin',  'Mwangi',  'K5566778E', '1987-11-30', 'kevin.mwangi@example.com'
    UNION ALL SELECT 'Faith',  'Achieng', 'F9988776F', '1998-06-21', 'faith.achieng@example.com'
    UNION ALL SELECT 'Samuel', 'Kiptoo',  'S3344556G', '1985-01-09', 'samuel.kiptoo@example.com'
    UNION ALL SELECT 'Mercy',  'Wambui',  'M7788990H', '1994-09-14', 'mercy.wambui@example.com'
    UNION ALL SELECT 'Peter',  'Omondi',  'P2468135J', '1991-04-25', 'peter.omondi@example.com'
    UNION ALL SELECT 'Lucy',   'Chebet',  'L1357924K', '1996-12-05', 'lucy.chebet@example.com'
) AS v
JOIN users u ON u.email = v.email;

INSERT INTO passengers (first_name, last_name, passport_number, date_of_birth) VALUES
('John', 'Doe', 'C9876543D', '1988-11-23');

-- Bookings (passenger_id 1 = Alice, passenger_id 10 = John)
INSERT INTO bookings (user_id, booking_reference, passenger_id, flight_id, price, payment_status) VALUES
(1,    'ABC123', 1,  1, 850.50,  'paid'),     -- Alice on flight 1 (NBO -> LHR)
(NULL, 'XYZ987', 10, 2, 1200.00, 'pending');  -- John on flight 2 (JFK -> LHR)

-- Alice's ticket: seat 1A on KQ100
INSERT INTO tickets (booking_id, flight_id, seat_id, boarding_time) VALUES
(1, 1, 1, '2026-11-15 07:45:00');

INSERT INTO crew_members (first_name, last_name, staff_role, passport_number) VALUES
('David', 'Kimani',  'captain',          'KE-P7721A'),
('Sarah', 'Jenkins', 'flight_attendant', 'UK-F8839B');

INSERT INTO flight_crew (flight_id, crew_id) VALUES
(1, 1),  -- Captain David on KQ100
(1, 2);  -- Flight attendant Sarah on KQ100

INSERT INTO baggage (ticket_id, weight_kg, tracking_barcode, baggage_status) VALUES
(1, 22.50, 'BAGG-KQ100-001A', 'loaded');

INSERT INTO loyalty_programs (user_id, membership_number, miles_balance, tier_level) VALUES
(1, 'FF-NBO-99542', 4500, 'silver');


-- =====================================================================
--  7. CHECKS
-- =====================================================================

-- Every user should show a first name (otherwise they cannot book)
SELECT u.user_id, u.email, p.first_name, p.last_name
FROM users u LEFT JOIN passengers p ON p.user_id = u.user_id;

-- Seats still free on each flight (flight 1 should not list 1A)
SELECT * FROM view_available_seats ORDER BY flight_id, seat_id;

-- Full ticket details
SELECT
    b.booking_reference,
    CONCAT(p.first_name, ' ', p.last_name) AS passenger_name,
    f.flight_number,
    f.departure_airport,
    f.arrival_airport,
    a.aircraft_model,
    s.seat_number,
    s.cabin_class,
    t.boarding_time
FROM tickets t
JOIN bookings   b ON t.booking_id   = b.booking_id
JOIN passengers p ON b.passenger_id = p.passenger_id
JOIN flights    f ON t.flight_id    = f.flight_id
JOIN aircrafts  a ON f.aircraft_id  = a.aircraft_id
JOIN seats      s ON t.seat_id      = s.seat_id;

-- Tickets with loyalty and baggage details
SELECT
    t.ticket_id,
    b.booking_reference,
    CONCAT(p.first_name, ' ', p.last_name) AS passenger,
    lp.membership_number AS frequent_flyer_no,
    lp.tier_level,
    f.flight_number,
    bg.tracking_barcode AS bag_tag,
    bg.weight_kg AS bag_weight
FROM tickets t
JOIN bookings   b ON t.booking_id   = b.booking_id
JOIN passengers p ON b.passenger_id = p.passenger_id
JOIN flights    f ON t.flight_id    = f.flight_id
LEFT JOIN users u ON b.user_id = u.user_id
LEFT JOIN loyalty_programs lp ON u.user_id = lp.user_id
LEFT JOIN baggage bg ON t.ticket_id = bg.ticket_id;