CREATE TABLE IF NOT EXISTS devices (
    id INT AUTO_INCREMENT PRIMARY KEY,
    device_id VARCHAR(50) UNIQUE NOT NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    altitude DOUBLE NOT NULL,
    speed DOUBLE NOT NULL,
    direction DOUBLE NOT NULL,
    gps_time DATETIME NOT NULL,
    positioned TINYINT(1) NOT NULL,
    alarm_flags VARCHAR(20) NOT NULL,
    status_flags VARCHAR(20) NOT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 0,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS device_history (
    id INT AUTO_INCREMENT PRIMARY KEY,
    device_id VARCHAR(50) NOT NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    altitude DOUBLE NOT NULL,
    speed DOUBLE NOT NULL,
    direction DOUBLE NOT NULL,
    gps_time DATETIME NOT NULL,
    positioned TINYINT(1) NOT NULL,
    alarm_flags VARCHAR(20) NOT NULL,
    status_flags VARCHAR(20) NOT NULL,
    received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX (device_id),
    INDEX (gps_time)
);

CREATE TABLE IF NOT EXISTS device_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    device_id VARCHAR(50) NOT NULL,
    message_id VARCHAR(10) NOT NULL,
    message_name VARCHAR(100) NOT NULL,
    serial_number INT NOT NULL,
    body_hex TEXT,
    checksum_valid TINYINT(1) NOT NULL,
    received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX (device_id)
);

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('admin', 'editor', 'viewer') DEFAULT 'viewer',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS device_metadata (
    device_id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) DEFAULT NULL,
    color VARCHAR(20) DEFAULT NULL,
    car_type VARCHAR(50) DEFAULT NULL,
    additional_data JSON DEFAULT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Seed default admin user: admin / admin123
INSERT INTO users (username, password_hash, role)
VALUES ('admin', '2407891470da683c628025a178659102c91a32958229ccce8c0c1694db6e568b', 'admin')
ON DUPLICATE KEY UPDATE username=username;
