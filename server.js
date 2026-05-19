const net = require('net');
const fs = require('fs');
const path = require('path');
const http = require('http');
const WebSocket = require('ws');

const PORT = 8000;
const LOG_FILE = path.join(__dirname, 'log.txt');
const PARSED_LOG = path.join(__dirname, 'parsed_log.txt');

// Keep track of all active devices and their latest location
const activeDevices = {};

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
    ws.send(JSON.stringify({
        type: 'devices_state',
        data: Object.values(activeDevices)
    }));

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
    const message = JSON.stringify({
        type: 'location_update',
        data: deviceData
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

server.listen(PORT, '0.0.0.0', () => {
    console.log(`=== JT808 GPS Tracker Server ===`);
    console.log(`Combined TCP/WS Port:  ${PORT}`);
    console.log(`Raw log:               ${LOG_FILE}`);
    console.log(`Parsed log:            ${PARSED_LOG}`);
    console.log(`================================`);
});
