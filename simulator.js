/**
 * JT808 GPS Simulator
 * Simulates 3 cars sending real-time location reports to the gateway server over TCP.
 */

const net = require('net');

// const SERVER_HOST = '127.0.0.1';
// const SERVER_PORT = 8000;

//ws://176.45.55.56:3000
// const SERVER_HOST = '169.58.198.222';
const SERVER_HOST = 'localhost';
const SERVER_PORT = 8000;
const SEND_INTERVAL_MS = 3000; // Send location every 3 seconds

// 3 Simulated cars with different IDs, starting coordinates, speed, and heading
const cars = [
    {
        id: '019176335601',
        name: 'Sedan Car (Red)',
        lat: 24.573213,
        lng: 46.546881,
        speed: 45.0, // km/h
        direction: 90, // heading East
        altitude: 600,
        serial: 1
    },
    {
        id: '019176335602',
        name: 'SUV Truck (Blue)',
        lat: 24.568100,
        lng: 46.551200,
        speed: 60.0, // km/h
        direction: 180, // heading South
        altitude: 610,
        serial: 1
    },
    {
        id: '019176335603',
        name: 'Delivery Van (Green)',
        lat: 24.576500,
        lng: 46.540100,
        speed: 30.0, // km/h
        direction: 270, // heading West
        altitude: 595,
        serial: 1
    }
];

// BCD conversion helper
function strToBcd(str) {
    const buf = Buffer.alloc(str.length / 2);
    for (let i = 0; i < str.length; i += 2) {
        buf[i / 2] = parseInt(str.substr(i, 2), 16);
    }
    return buf;
}

// Calculate XOR checksum
function xorChecksum(buf) {
    let cs = 0;
    for (let i = 0; i < buf.length; i++) {
        cs ^= buf[i];
    }
    return cs;
}

// Escape JT808 sequences (0x7E -> 0x7D 0x02, 0x7D -> 0x7D 0x01)
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

// Build 0x0200 Location Report Packet
function buildLocationReport(phoneStr, serial, lat, lng, speedVal, directionVal, altitudeVal) {
    // 1. Prepare Body (28 bytes)
    const body = Buffer.alloc(28);
    body.writeUInt32BE(0, 0); // alarmFlags: 0
    body.writeUInt32BE(0x02, 4); // statusFlags: 0x02 (positioned)
    body.writeUInt32BE(Math.floor(lat * 1000000), 8); // latitude: degrees * 10^6
    body.writeUInt32BE(Math.floor(lng * 1000000), 12); // longitude: degrees * 10^6
    body.writeUInt16BE(altitudeVal, 16); // altitude
    body.writeUInt16BE(Math.floor(speedVal * 10), 18); // speed: km/h * 10
    body.writeUInt16BE(directionVal, 20); // direction

    // BCD timestamp: YY MM DD HH MM SS (UTC)
    const now = new Date();
    const yy = String(now.getUTCFullYear() % 100).padStart(2, '0');
    const mm = String(now.getUTCMonth() + 1).padStart(2, '0');
    const dd = String(now.getUTCDate()).padStart(2, '0');
    const hh = String(now.getUTCHours()).padStart(2, '0');
    const min = String(now.getUTCMinutes()).padStart(2, '0');
    const ss = String(now.getUTCSeconds()).padStart(2, '0');
    const bcdTime = strToBcd(yy + mm + dd + hh + min + ss);
    bcdTime.copy(body, 22);

    // 2. Prepare Header (12 bytes)
    const header = Buffer.alloc(12);
    header.writeUInt16BE(0x0200, 0); // MsgID (Location Report)
    header.writeUInt16BE(body.length, 2); // Body length properties
    const phoneBcd = strToBcd(phoneStr.padStart(12, '0'));
    phoneBcd.copy(header, 4); // BCD Phone ID
    header.writeUInt16BE(serial, 10); // Msg Serial

    // 3. Compute Checksum
    const payload = Buffer.concat([header, body]);
    const checksum = xorChecksum(payload);

    // 4. Escape sequences
    const escapedPayload = jt808Escape(payload);
    const escapedChecksum = jt808Escape(Buffer.from([checksum]));

    // 5. Framing
    return Buffer.concat([
        Buffer.from([0x7E]),
        escapedPayload,
        escapedChecksum,
        Buffer.from([0x7E])
    ]);
}

// Function to simulate movement (updates coordinates slightly based on direction and speed)
function updateCarPosition(car) {
    const speedMs = (car.speed / 3.6); // Convert speed to m/s
    const distanceMeters = speedMs * (SEND_INTERVAL_MS / 1000); // Distance covered in this step
    const earthRadius = 6378137; // in meters

    // Coordinate offset in radians
    const dLat = (distanceMeters * Math.cos((car.direction * Math.PI) / 180)) / earthRadius;
    const dLng = (distanceMeters * Math.sin((car.direction * Math.PI) / 180)) / (earthRadius * Math.cos((car.lat * Math.PI) / 180));

    // Update lat/lng
    car.lat += (dLat * 180) / Math.PI;
    car.lng += (dLng * 180) / Math.PI;

    // Slowly alter speed and direction to make it look realistic
    car.speed += (Math.random() - 0.5) * 5; // fluctuate speed by +/- 2.5 km/h
    if (car.speed < 10) car.speed = 10;
    if (car.speed > 100) car.speed = 100;

    car.direction = (car.direction + Math.round((Math.random() - 0.5) * 20)) % 360; // fluctuate direction
    if (car.direction < 0) car.direction += 360;
}

// Connect to the gateway server
const CONNECT_TIMEOUT_MS = 10000; // Consider it "no connection" if nothing happens within 10s
const client = new net.Socket();
client.setTimeout(CONNECT_TIMEOUT_MS);

console.log(`Connecting to JT808 Gateway Server at ${SERVER_HOST}:${SERVER_PORT}...`);

client.connect(SERVER_PORT, SERVER_HOST, () => {
    console.log('Connected to gateway! Starting car simulations...');
    client.setTimeout(0); // Connected - stop watching for a connect timeout

    // Start simulation loop
    setInterval(() => {
        cars.forEach((car) => {
            // Update position
            updateCarPosition(car);

            // Generate JT808 raw location packet
            const packet = buildLocationReport(
                car.id,
                car.serial++,
                car.lat,
                car.lng,
                car.speed,
                car.direction,
                car.altitude
            );

            // Send raw binary buffer over TCP
            if (!client.destroyed) {
                client.write(packet);
                console.log(`Sent update for ${car.name} (ID: ${car.id}): Lat=${car.lat.toFixed(6)}, Lng=${car.lng.toFixed(6)}, Speed=${car.speed.toFixed(1)} km/h, Heading=${car.direction}°`);
            }
        });
        console.log('--------------------------------------------------');
    }, SEND_INTERVAL_MS);
});

client.on('data', (data) => {
    // Show responses received from the platform gateway (e.g. general ACKs)
    console.log(`[Platform Reply] Received response buffer: ${data.toString('hex').toUpperCase()}`);
});

client.on('timeout', () => {
    console.error(`No connection: could not reach ${SERVER_HOST}:${SERVER_PORT} within ${CONNECT_TIMEOUT_MS / 1000}s (timed out).`);
    client.destroy();
});

client.on('error', (err) => {
    console.error(`No connection: ${err.message}`);
});

client.on('close', () => {
    console.log('Connection closed. Exiting simulator.');
    process.exit(0);
});
