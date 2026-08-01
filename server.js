require('dotenv').config();
const net = require('net');
const fs = require('fs');
const path = require('path');
const http = require('http');
const WebSocket = require('ws');
const mysql = require('mysql2/promise');

const PORT = 8000;
const LOG_FILE = path.join(__dirname, 'log.txt');
const PARSED_LOG = path.join(__dirname, 'parsed_log.txt');

// Database Connection Configuration
const DB_HOST = process.env.DB_HOST || 'localhost';
const DB_USER = process.env.DB_USER || 'root';
const DB_PASSWORD = process.env.DB_PASSWORD || '';
const DB_NAME = process.env.DB_NAME || 'gps_tracker';
const DB_PORT = process.env.DB_PORT || 3306;

let dbPool = null;

// Keep track of all active devices, their latest locations, and metadata cache
const activeDevices = {};
const deviceMetadata = {};

// Create dummy HTTP server to handle WebSocket handshakes
const httpServer = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('JT808 GPS Webhook Gateway\n');
});

// Create WebSocket server for app clients (no standalone port)
const wss = new WebSocket.Server({ noServer: true });

wss.on('connection', (ws, req) => {
    const clientIp = req.socket.remoteAddress;
    console.log(`[${new Date().toISOString()}] WebSocket client connected from ${clientIp}`);

    // Send the current active state of all devices immediately upon connection
    const decoratedDevices = Object.values(activeDevices).map(dev => {
        const meta = deviceMetadata[dev.deviceId] || {};
        return {
            ...dev,
            name: meta.name || null,
            color: meta.color || null,
            carType: meta.carType || null,
            additionalData: meta.additionalData || null
        };
    });
    ws.send(JSON.stringify({
        type: 'devices_state',
        data: decoratedDevices
    }));

    ws.on('message', async (message) => {
        try {
            const request = JSON.parse(message);
            if (request.type === 'get_devices') {
                let devices = Object.keys(activeDevices);
                if (dbPool) {
                    try {
                        const [rows] = await dbPool.query('SELECT DISTINCT device_id FROM device_history UNION SELECT DISTINCT device_id FROM devices');
                        const dbDevices = rows.map(r => r.device_id);
                        devices = Array.from(new Set([...devices, ...dbDevices]));
                    } catch (err) {
                        console.error('Error fetching devices list from DB:', err.message);
                    }
                }
                ws.send(JSON.stringify({
                    type: 'devices_list_response',
                    devices: devices
                }));
            } else if (request.type === 'get_history') {
                const { deviceId, date } = request;
                if (dbPool) {
                    const query = `
                        SELECT latitude, longitude, altitude, speed, direction, gps_time, positioned, alarm_flags, status_flags
                        FROM device_history
                        WHERE device_id = ? AND DATE(gps_time) = ?
                        ORDER BY gps_time ASC
                    `;
                    const [rows] = await dbPool.query(query, [deviceId, date]);
                    ws.send(JSON.stringify({
                        type: 'history_response',
                        deviceId: deviceId,
                        date: date,
                        history: rows
                    }));
                } else {
                    ws.send(JSON.stringify({
                        type: 'history_response',
                        deviceId: deviceId,
                        date: date,
                        history: []
                    }));
                }
            } else if (request.type === 'login') {
                const { username, password } = request;
                if (dbPool) {
                    const crypto = require('crypto');
                    const passHash = crypto.createHash('sha256').update(password).digest('hex');
                    try {
                        const [rows] = await dbPool.query('SELECT role FROM users WHERE username = ? AND password_hash = ?', [username, passHash]);
                        if (rows.length > 0) {
                            ws.send(JSON.stringify({
                                type: 'login_response',
                                success: true,
                                role: rows[0].role,
                                username: username
                            }));
                        } else {
                            ws.send(JSON.stringify({
                                type: 'login_response',
                                success: false,
                                message: 'Invalid username or password'
                            }));
                        }
                    } catch (err) {
                        console.error('Login DB Error:', err.message);
                        ws.send(JSON.stringify({ type: 'login_response', success: false, message: 'Server Database Error' }));
                    }
                } else {
                    if (username === 'admin' && password === 'admin123') {
                        ws.send(JSON.stringify({ type: 'login_response', success: true, role: 'admin', username: 'admin' }));
                    } else {
                        ws.send(JSON.stringify({ type: 'login_response', success: false, message: 'Invalid credentials' }));
                    }
                }
            } else if (request.type === 'update_device_metadata') {
                const { deviceId, name, color, carType, additionalData, role } = request;
                if (role !== 'admin' && role !== 'editor') {
                    ws.send(JSON.stringify({
                        type: 'update_device_metadata_response',
                        success: false,
                        message: 'Unauthorized: Viewer role cannot modify metadata.'
                    }));
                } else {
                    deviceMetadata[deviceId] = {
                        name,
                        color,
                        carType,
                        additionalData
                    };
                    if (dbPool) {
                        try {
                            const query = `
                                INSERT INTO device_metadata (device_id, name, color, car_type, additional_data)
                                VALUES (?, ?, ?, ?, ?)
                                ON DUPLICATE KEY UPDATE
                                    name = VALUES(name),
                                    color = VALUES(color),
                                    car_type = VALUES(car_type),
                                    additional_data = VALUES(additional_data)
                            `;
                            const serializedData = additionalData ? JSON.stringify(additionalData) : null;
                            await dbPool.query(query, [deviceId, name, color, carType, serializedData]);
                        } catch (err) {
                            console.error('Error saving device metadata:', err.message);
                        }
                    }
                    const decoratedUpdate = {
                        type: 'metadata_update',
                        deviceId,
                        name,
                        color,
                        carType,
                        additionalData
                    };
                    wss.clients.forEach((client) => {
                        if (client.readyState === WebSocket.OPEN) {
                            client.send(JSON.stringify(decoratedUpdate));
                        }
                    });
                    if (activeDevices[deviceId]) {
                        activeDevices[deviceId] = {
                            ...activeDevices[deviceId],
                            name,
                            color,
                            carType,
                            additionalData
                        };
                    }
                }
            }
        } catch (e) {
            console.error(`[${new Date().toISOString()}] Error handling WebSocket client message:`, e.message);
        }
    });

    ws.on('close', () => {
        console.log(`[${new Date().toISOString()}] WebSocket client disconnected: ${clientIp}`);
    });

    ws.on('error', (err) => {
        console.error(`[${new Date().toISOString()}] WebSocket error for ${clientIp}:`, err.message);
    });
});

// Pass HTTP upgrade requests to the WebSocket server
httpServer.on('upgrade', (req, socket, head) => {
    wss.handleUpgrade(req, socket, head, (ws) => {
        wss.emit('connection', ws, req);
    });
});

// Broadcast parsed location data to all connected WebSocket clients
function broadcastLocation(deviceData) {
    const meta = deviceMetadata[deviceData.deviceId] || {};
    const decoratedData = {
        ...deviceData,
        name: meta.name || null,
        color: meta.color || null,
        carType: meta.carType || null,
        additionalData: meta.additionalData || null
    };
    const message = JSON.stringify({
        type: 'location_update',
        data: decoratedData
    });
    wss.clients.forEach((client) => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(message);
        }
    });
}

// Ensure log files exist
if (!fs.existsSync(LOG_FILE)) fs.writeFileSync(LOG_FILE, '', 'utf8');
if (!fs.existsSync(PARSED_LOG)) fs.writeFileSync(PARSED_LOG, '', 'utf8');

// ============== JT808 Protocol Helpers ==============

// Unescape JT808 data (reverse escape sequences in the payload between 0x7E markers)
function jt808Unescape(buf) {
    const result = [];
    for (let i = 0; i < buf.length; i++) {
        if (buf[i] === 0x7D && i + 1 < buf.length) {
            if (buf[i + 1] === 0x02) {
                result.push(0x7E);
                i++;
            } else if (buf[i + 1] === 0x01) {
                result.push(0x7D);
                i++;
            } else {
                result.push(buf[i]);
            }
        } else {
            result.push(buf[i]);
        }
    }
    return Buffer.from(result);
}

// Escape JT808 data before framing with 0x7E
function jt808Escape(buf) {
    const result = [];
    for (let i = 0; i < buf.length; i++) {
        if (buf[i] === 0x7E) {
            result.push(0x7D, 0x02);
        } else if (buf[i] === 0x7D) {
            result.push(0x7D, 0x01);
        } else {
            result.push(buf[i]);
        }
    }
    return Buffer.from(result);
}

// Calculate XOR checksum over a buffer
function xorChecksum(buf) {
    let cs = 0;
    for (let i = 0; i < buf.length; i++) {
        cs ^= buf[i];
    }
    return cs;
}

// Extract packets from raw TCP buffer (split by 0x7E delimiters)
function extractPackets(buffer) {
    const packets = [];
    let start = -1;

    for (let i = 0; i < buffer.length; i++) {
        if (buffer[i] === 0x7E) {
            if (start === -1) {
                start = i; // Mark start of packet
            } else {
                // Found end of packet - extract content between the two 0x7E markers
                if (i - start > 1) { // Must have content between markers
                    const rawContent = buffer.slice(start + 1, i);
                    const unescaped = jt808Unescape(rawContent);
                    packets.push(unescaped);
                }
                start = -1; // Reset for next packet
            }
        }
    }

    // Return remaining unprocessed bytes (incomplete packet)
    let remaining = Buffer.alloc(0);
    if (start !== -1) {
        remaining = buffer.slice(start);
    }

    return { packets, remaining };
}

// Parse a JT808 message header
// Header: MsgID(2) + BodyProps(2) + Phone(6) + MsgSerial(2) = 12 bytes
function parseHeader(buf) {
    if (buf.length < 12) return null;

    const msgId = buf.readUInt16BE(0);
    const bodyProps = buf.readUInt16BE(2);
    const bodyLength = bodyProps & 0x03FF; // Lower 10 bits = body length
    const phone = buf.slice(4, 10); // 6 bytes BCD phone/terminal ID
    const msgSerial = buf.readUInt16BE(10);
    const body = buf.slice(12, 12 + bodyLength);
    const checkByte = buf.length > 12 + bodyLength ? buf[12 + bodyLength] : null;

    // Verify checksum
    const dataForCheck = buf.slice(0, 12 + bodyLength);
    const calculatedCheck = xorChecksum(dataForCheck);

    return {
        msgId,
        bodyProps,
        bodyLength,
        phone,
        phoneHex: phone.toString('hex').toUpperCase(),
        msgSerial,
        body,
        checkByte,
        checksumValid: checkByte === null || checkByte === calculatedCheck,
        calculatedCheck
    };
}

// Build a JT808 response packet
function buildResponse(msgId, phone, serverSerial, body) {
    const bodyLen = body ? body.length : 0;
    const header = Buffer.alloc(12);
    header.writeUInt16BE(msgId, 0);          // Response Message ID
    header.writeUInt16BE(bodyLen, 2);         // Body Properties (just length)
    phone.copy(header, 4);                    // Copy phone/terminal ID
    header.writeUInt16BE(serverSerial, 10);   // Server serial number

    const payload = body ? Buffer.concat([header, body]) : header;
    const checksum = xorChecksum(payload);

    const escaped = jt808Escape(payload);
    const frame = Buffer.alloc(escaped.length + 3); // 0x7E + escaped + checksum_escaped + 0x7E

    // Build: 0x7E + escape(payload) + escape(checksum) + 0x7E
    const checksumBuf = Buffer.from([checksum]);
    const escapedChecksum = jt808Escape(checksumBuf);
    const fullFrame = Buffer.concat([
        Buffer.from([0x7E]),
        escaped,
        escapedChecksum,
        Buffer.from([0x7E])
    ]);

    return fullFrame;
}

// Build Platform General Response (0x8001)
function buildGeneralResponse(phone, serverSerial, responseMsgSerial, responseMsgId, result) {
    const body = Buffer.alloc(5);
    body.writeUInt16BE(responseMsgSerial, 0); // Responding to this serial
    body.writeUInt16BE(responseMsgId, 2);     // Responding to this message type
    body.writeUInt8(result, 4);               // 0 = success
    return buildResponse(0x8001, phone, serverSerial, body);
}

// Build Registration Response (0x8100)
function buildRegistrationResponse(phone, serverSerial, responseMsgSerial, result, authCode) {
    const authBuf = Buffer.from(authCode, 'utf8');
    const body = Buffer.alloc(3 + authBuf.length);
    body.writeUInt16BE(responseMsgSerial, 0); // Responding to this serial
    body.writeUInt8(result, 2);               // 0 = success
    authBuf.copy(body, 3);                    // Auth code
    return buildResponse(0x8100, phone, serverSerial, body);
}

// Get message type name
function getMsgName(msgId) {
    const names = {
        0x0001: 'Terminal General Response',
        0x0002: 'Terminal Heartbeat',
        0x0003: 'Terminal Unregister',
        0x0100: 'Terminal Registration',
        0x0102: 'Terminal Authentication',
        0x0200: 'Location Report',
        0x0201: 'Location Query Response',
        0x0704: 'Bulk Location Upload',
        0x0900: 'Data Uplink Transparent',
    };
    return names[msgId] || `Unknown (0x${msgId.toString(16).padStart(4, '0')})`;
}

// Parse location data from 0x0200 body
function parseLocationBody(body) {
    if (body.length < 28) return null;

    const alarmFlags = body.readUInt32BE(0);
    const statusFlags = body.readUInt32BE(4);
    const latitude = body.readUInt32BE(8) / 1000000;   // Degrees * 10^6
    const longitude = body.readUInt32BE(12) / 1000000;  // Degrees * 10^6
    const altitude = body.readUInt16BE(16);
    const speed = body.readUInt16BE(18) / 10;            // km/h * 10
    const direction = body.readUInt16BE(20);
    // BCD timestamp: YY MM DD HH MM SS
    const timeBCD = body.slice(22, 28);
    const timeStr = `20${bcdToStr(timeBCD[0])}/${bcdToStr(timeBCD[1])}/${bcdToStr(timeBCD[2])} ${bcdToStr(timeBCD[3])}:${bcdToStr(timeBCD[4])}:${bcdToStr(timeBCD[5])}`;

    // Check south/west flags in status
    const isSouth = (statusFlags >> 2) & 1;
    const isWest = (statusFlags >> 3) & 1;

    return {
        alarmFlags: `0x${alarmFlags.toString(16).padStart(8, '0')}`,
        statusFlags: `0x${statusFlags.toString(16).padStart(8, '0')}`,
        latitude: isSouth ? -latitude : latitude,
        longitude: isWest ? -longitude : longitude,
        altitude,
        speed,
        direction,
        time: timeStr,
        positioned: !!(statusFlags & 0x02)
    };
}

function bcdToStr(byte) {
    return ((byte >> 4) & 0x0F).toString() + (byte & 0x0F).toString();
}

// Format hex dump for logging
function hexDump(buf) {
    const hex = buf.toString('hex').toUpperCase();
    return hex.match(/.{1,2}/g)?.join(' ') || '';
}

// ============== Database Initialization & Helpers ==============

async function initDatabase() {
    try {
        console.log(`[${new Date().toISOString()}] Initializing connection to MySQL server at ${DB_HOST}:${DB_PORT}...`);
        
        // Connect to MySQL server first to ensure DB exists
        const connection = await mysql.createConnection({
            host: DB_HOST,
            user: DB_USER,
            password: DB_PASSWORD,
            port: DB_PORT
        });
        await connection.query(`CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;`);
        await connection.end();

        // Create connection pool
        dbPool = mysql.createPool({
            host: DB_HOST,
            user: DB_USER,
            password: DB_PASSWORD,
            database: DB_NAME,
            port: DB_PORT,
            waitForConnections: true,
            connectionLimit: 10,
            queueLimit: 0
        });

        console.log(`[${new Date().toISOString()}] Connected to MySQL database "${DB_NAME}"`);

        // Create tables if they do not exist
        await dbPool.query(`
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
                last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            );
        `);

        await dbPool.query(`
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
        `);

        await dbPool.query(`
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
        `);

        await dbPool.query(`
            CREATE TABLE IF NOT EXISTS users (
                id INT AUTO_INCREMENT PRIMARY KEY,
                username VARCHAR(50) UNIQUE NOT NULL,
                password_hash VARCHAR(255) NOT NULL,
                role ENUM('admin', 'editor', 'viewer') DEFAULT 'viewer',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        `);

        await dbPool.query(`
            CREATE TABLE IF NOT EXISTS device_metadata (
                device_id VARCHAR(50) PRIMARY KEY,
                name VARCHAR(100) DEFAULT NULL,
                color VARCHAR(20) DEFAULT NULL,
                car_type VARCHAR(50) DEFAULT NULL,
                additional_data JSON DEFAULT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            );
        `);

        // Seed default admin user if none exists
        const [userRows] = await dbPool.query('SELECT id FROM users LIMIT 1');
        if (userRows.length === 0) {
            const crypto = require('crypto');
            const defaultPassHash = crypto.createHash('sha256').update('admin123').digest('hex');
            await dbPool.query('INSERT INTO users (username, password_hash, role) VALUES (?, ?, ?)', ['admin', defaultPassHash, 'admin']);
            console.log(`[${new Date().toISOString()}] Default admin user created (username: admin, password: admin123)`);
        }

        // Load device metadata cache
        const [metaRows] = await dbPool.query('SELECT * FROM device_metadata');
        for (const row of metaRows) {
            deviceMetadata[row.device_id] = {
                name: row.name,
                color: row.color,
                carType: row.car_type,
                additionalData: typeof row.additional_data === 'string' ? JSON.parse(row.additional_data) : row.additional_data
            };
        }

        console.log(`[${new Date().toISOString()}] Database schema initialized successfully (${metaRows.length} metadata loaded)`);
    } catch (err) {
        console.error(`[${new Date().toISOString()}] Database initialization failed:`, err.message);
        console.log('Server will continue running, but database features will be disabled/mocked.');
        dbPool = null;
    }
}

// Database logging helper
async function logDeviceMessage(deviceId, msgId, msgName, serialNumber, bodyHex, checksumValid) {
    if (!dbPool) return;
    try {
        const query = `
            INSERT INTO device_logs (device_id, message_id, message_name, serial_number, body_hex, checksum_valid)
            VALUES (?, ?, ?, ?, ?, ?)
        `;
        await dbPool.query(query, [
            deviceId,
            `0x${msgId.toString(16).toUpperCase().padStart(4, '0')}`,
            msgName,
            serialNumber,
            bodyHex,
            checksumValid ? 1 : 0
        ]);
    } catch (err) {
        console.error(`[${new Date().toISOString()}] Failed to log message to DB:`, err.message);
    }
}

// Database location helper
async function saveDeviceLocation(deviceData) {
    if (!dbPool) return;
    try {
        // Convert time format like "2026/08/01 15:26:56" to "2026-08-01 15:26:56"
        let formattedTime = null;
        if (deviceData.time) {
            formattedTime = deviceData.time.replace(/\//g, '-');
        } else {
            formattedTime = new Date().toISOString().slice(0, 19).replace('T', ' ');
        }

        // Insert or update latest device state
        const queryDevice = `
            INSERT INTO devices (device_id, latitude, longitude, altitude, speed, direction, gps_time, positioned, alarm_flags, status_flags)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                latitude = VALUES(latitude),
                longitude = VALUES(longitude),
                altitude = VALUES(altitude),
                speed = VALUES(speed),
                direction = VALUES(direction),
                gps_time = VALUES(gps_time),
                positioned = VALUES(positioned),
                alarm_flags = VALUES(alarm_flags),
                status_flags = VALUES(status_flags)
        `;
        await dbPool.query(queryDevice, [
            deviceData.deviceId,
            deviceData.latitude,
            deviceData.longitude,
            deviceData.altitude,
            deviceData.speed,
            deviceData.direction,
            formattedTime,
            deviceData.positioned ? 1 : 0,
            deviceData.alarmFlags,
            deviceData.statusFlags
        ]);

        // Insert into history log
        const queryHistory = `
            INSERT INTO device_history (device_id, latitude, longitude, altitude, speed, direction, gps_time, positioned, alarm_flags, status_flags)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        `;
        await dbPool.query(queryHistory, [
            deviceData.deviceId,
            deviceData.latitude,
            deviceData.longitude,
            deviceData.altitude,
            deviceData.speed,
            deviceData.direction,
            formattedTime,
            deviceData.positioned ? 1 : 0,
            deviceData.alarmFlags,
            deviceData.statusFlags
        ]);
    } catch (err) {
        console.error(`[${new Date().toISOString()}] Failed to save location to DB:`, err.message);
    }
}

// ============== Server ==============

let serverSerial = 0; // Server-side message serial counter

// Handle raw JT808 TCP GPS tracker sockets
function handleGpsTracker(socket) {
    const clientAddress = `${socket.remoteAddress}:${socket.remotePort}`;
    let clientBuffer = Buffer.alloc(0); // Accumulate TCP stream data
    let devicePhone = null; // Store device phone/ID after first message

    socket.on('data', (data) => {
        const now = new Date().toISOString();
        console.log(`[${now}] Raw data from ${clientAddress}: ${hexDump(data)}`);

        // Log raw hex data
        const rawLogEntry = `--- Received Raw Data ---
Time: ${now}
From: ${clientAddress}
Hex: ${hexDump(data)}
Length: ${data.length} bytes
-----------------------------\n`;
        fs.appendFile(LOG_FILE, rawLogEntry, () => {});

        // Accumulate data in buffer
        clientBuffer = Buffer.concat([clientBuffer, data]);

        // Extract complete packets
        const { packets, remaining } = extractPackets(clientBuffer);
        clientBuffer = remaining;

        // Process each packet
        for (const packet of packets) {
            const header = parseHeader(packet);

            if (!header) {
                console.log(`[${now}] Could not parse packet header: ${hexDump(packet)}`);
                const unknownLog = `--- Unparseable Packet ---
Time: ${now}
From: ${clientAddress}
Hex: ${hexDump(packet)}
-----------------------------\n`;
                fs.appendFile(PARSED_LOG, unknownLog, () => {});
                continue;
            }

            // Store the device phone/ID
            if (!devicePhone) {
                devicePhone = header.phone;
            }

            const msgName = getMsgName(header.msgId);
            console.log(`[${now}] Message: ${msgName} | Serial: ${header.msgSerial} | Phone: ${header.phoneHex} | Body: ${hexDump(header.body)} | Checksum: ${header.checksumValid ? 'OK' : 'FAIL'}`);

            let parsedLog = `--- Parsed JT808 Message ---
Time: ${now}
From: ${clientAddress}
Message: ${msgName} (0x${header.msgId.toString(16).padStart(4, '0')})
Phone/ID: ${header.phoneHex}
Serial: ${header.msgSerial}
Body Length: ${header.bodyLength}
Body Hex: ${hexDump(header.body)}
Checksum: ${header.checksumValid ? 'VALID' : 'INVALID (expected 0x' + header.calculatedCheck.toString(16) + ', got 0x' + (header.checkByte || 0).toString(16) + ')'}`;

            // Log message to database asynchronously
            logDeviceMessage(header.phoneHex, header.msgId, msgName, header.msgSerial, hexDump(header.body), header.checksumValid);

            // Handle specific message types
            let response = null;
            serverSerial++;

            switch (header.msgId) {
                case 0x0100: // Terminal Registration
                    console.log(`[${now}] >>> Terminal Registration from ${header.phoneHex}`);
                    parsedLog += `\nAction: Sending Registration Response (auth code: OK)`;
                    response = buildRegistrationResponse(
                        header.phone,
                        serverSerial,
                        header.msgSerial,
                        0,       // 0 = success
                        'OK'     // Auth code
                    );
                    break;

                case 0x0102: // Terminal Authentication
                    console.log(`[${now}] >>> Terminal Authentication from ${header.phoneHex}`);
                    parsedLog += `\nAuth Data: ${header.body.toString('utf8')}`;
                    parsedLog += `\nAction: Sending General Response (success)`;
                    response = buildGeneralResponse(
                        header.phone, serverSerial,
                        header.msgSerial, header.msgId, 0
                    );
                    break;

                case 0x0002: // Terminal Heartbeat
                    console.log(`[${now}] >>> Heartbeat from ${header.phoneHex}`);
                    parsedLog += `\nAction: Sending Heartbeat Response`;
                    response = buildGeneralResponse(
                        header.phone, serverSerial,
                        header.msgSerial, header.msgId, 0
                    );
                    break;

                case 0x0003: // Terminal Unregister (some devices use as heartbeat)
                    console.log(`[${now}] >>> Unregister/Heartbeat (0x0003) from ${header.phoneHex}`);
                    parsedLog += `\nAction: Sending General Response (treating as heartbeat)`;
                    response = buildGeneralResponse(
                        header.phone, serverSerial,
                        header.msgSerial, header.msgId, 0
                    );
                    break;

                case 0x0200: // Location Report
                    const loc = parseLocationBody(header.body);
                    if (loc) {
                        console.log(`[${now}] >>> Location: Lat=${loc.latitude}, Lon=${loc.longitude}, Speed=${loc.speed}km/h, Alt=${loc.altitude}m, Time=${loc.time}, GPS=${loc.positioned ? 'YES' : 'NO'}`);
                        parsedLog += `\n--- GPS DATA ---`;
                        parsedLog += `\nLatitude: ${loc.latitude}`;
                        parsedLog += `\nLongitude: ${loc.longitude}`;
                        parsedLog += `\nAltitude: ${loc.altitude}m`;
                        parsedLog += `\nSpeed: ${loc.speed} km/h`;
                        parsedLog += `\nDirection: ${loc.direction}°`;
                        parsedLog += `\nGPS Time: ${loc.time}`;
                        parsedLog += `\nPositioned: ${loc.positioned ? 'YES' : 'NO'}`;
                        parsedLog += `\nAlarm: ${loc.alarmFlags}`;
                        parsedLog += `\nStatus: ${loc.statusFlags}`;

                        // Store device location update in memory
                        const deviceId = header.phoneHex;
                        const deviceData = {
                            deviceId: deviceId,
                            latitude: loc.latitude,
                            longitude: loc.longitude,
                            altitude: loc.altitude,
                            speed: loc.speed,
                            direction: loc.direction,
                            time: loc.time,
                            positioned: loc.positioned,
                            alarmFlags: loc.alarmFlags,
                            statusFlags: loc.statusFlags,
                            lastUpdated: new Date().toISOString()
                        };
                        activeDevices[deviceId] = deviceData;

                        // Save to MySQL Database
                        saveDeviceLocation(deviceData);

                        // Broadcast to connected web/app listeners
                        broadcastLocation(deviceData);
                    }
                    parsedLog += `\nAction: Sending Location ACK`;
                    response = buildGeneralResponse(
                        header.phone, serverSerial,
                        header.msgSerial, header.msgId, 0
                    );
                    break;

                case 0x0001: // Terminal General Response (device acknowledging our commands)
                    console.log(`[${now}] >>> Device ACK received`);
                    parsedLog += `\nAction: No response needed (device ACK)`;
                    break;

                default:
                    console.log(`[${now}] >>> Unknown message 0x${header.msgId.toString(16).padStart(4, '0')} — sending general ACK`);
                    parsedLog += `\nAction: Sending General Response (ACK for unknown message)`;
                    response = buildGeneralResponse(
                        header.phone, serverSerial,
                        header.msgSerial, header.msgId, 0
                    );
                    break;
            }

            parsedLog += `\n-----------------------------\n`;
            fs.appendFile(PARSED_LOG, parsedLog, () => {});

            // Send response back to device
            if (response && !socket.destroyed) {
                socket.write(response);
                console.log(`[${now}] <<< Sent response: ${hexDump(response)}`);
            }
        }
    });

    socket.on('end', () => {
        console.log(`[${new Date().toISOString()}] Client disconnected: ${clientAddress}`);
    });

    socket.on('error', (err) => {
        console.error(`Socket error for ${clientAddress}:`, err.message);
    });

    socket.on('close', () => {
        console.log(`[${new Date().toISOString()}] Connection closed: ${clientAddress}`);
    });
}

// Multiplexed raw TCP Server
const server = net.createServer((socket) => {
    // Peek at the first chunk of data to determine protocol
    socket.once('data', (chunk) => {
        const firstByte = chunk[0];

        // HTTP requests start with 'G' (GET), 'P' (POST), 'H' (HEAD), 'O' (OPTIONS), etc.
        const isHttp = firstByte === 0x47 || firstByte === 0x50 || firstByte === 0x48 || firstByte === 0x4f || firstByte === 0x55 || firstByte === 0x44;

        // Push the chunk back so the corresponding parser reads it
        socket.unshift(chunk);

        if (isHttp) {
            // Forward HTTP/WebSocket connections to the HTTP Server
            httpServer.emit('connection', socket);
        } else {
            // Handle as JT808 TCP Tracker
            const clientAddress = `${socket.remoteAddress}:${socket.remotePort}`;
            console.log(`[${new Date().toISOString()}] JT808 Client connected: ${clientAddress}`);
            handleGpsTracker(socket);
        }
    });
});

server.on('error', (err) => {
    console.error('Server error:', err.message);
});

// Initialize Database, then start server
initDatabase().then(() => {
    server.listen(PORT, '0.0.0.0', () => {
        console.log(`=== JT808 GPS Tracker Server ===`);
        console.log(`Combined TCP/WS Port:  ${PORT}`);
        console.log(`Raw log:               ${LOG_FILE}`);
        console.log(`Parsed log:            ${PARSED_LOG}`);
        console.log(`================================`);
    });
});
