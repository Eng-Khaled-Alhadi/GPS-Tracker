package com.gps.tracker.util;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

public class Jt808Helper {

    public static byte[] jt808Unescape(byte[] buf) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        for (int i = 0; i < buf.length; i++) {
            if ((buf[i] & 0xFF) == 0x7D && i + 1 < buf.length) {
                int next = buf[i + 1] & 0xFF;
                if (next == 0x02) {
                    out.write(0x7E);
                    i++;
                } else if (next == 0x01) {
                    out.write(0x7D);
                    i++;
                } else {
                    out.write(buf[i]);
                }
            } else {
                out.write(buf[i]);
            }
        }
        return out.toByteArray();
    }

    public static byte[] jt808Escape(byte[] buf) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        for (byte b : buf) {
            int value = b & 0xFF;
            if (value == 0x7E) {
                out.write(0x7D);
                out.write(0x02);
            } else if (value == 0x7D) {
                out.write(0x7D);
                out.write(0x01);
            } else {
                out.write(b);
            }
        }
        return out.toByteArray();
    }

    public static byte xorChecksum(byte[] buf, int offset, int length) {
        byte cs = 0;
        for (int i = offset; i < offset + length; i++) {
            cs ^= buf[i];
        }
        return cs;
    }

    public static byte xorChecksum(byte[] buf) {
        return xorChecksum(buf, 0, buf.length);
    }

    public static String bcdToStr(byte[] bcd) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bcd) {
            sb.append((b >> 4) & 0x0F);
            sb.append(b & 0x0F);
        }
        return sb.toString();
    }

    public static String bcdByteToStr(byte b) {
        return String.valueOf((b >> 4) & 0x0F) + (b & 0x0F);
    }

    public static String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02X ", b));
        }
        return sb.toString().trim();
    }

    public static byte[] hexToBytes(String s) {
        int len = s.length();
        byte[] data = new byte[len / 2];
        for (int i = 0; i < len; i += 2) {
            data[i / 2] = (byte) ((Character.digit(s.charAt(i), 16) << 4)
                                 + Character.digit(s.charAt(i+1), 16));
        }
        return data;
    }

    public static class PacketExtractionResult {
        public List<byte[]> packets;
        public byte[] remaining;

        public PacketExtractionResult(List<byte[]> packets, byte[] remaining) {
            this.packets = packets;
            this.remaining = remaining;
        }
    }

    public static PacketExtractionResult extractPackets(byte[] buffer) {
        List<byte[]> packets = new ArrayList<>();
        int start = -1;

        for (int i = 0; i < buffer.length; i++) {
            if ((buffer[i] & 0xFF) == 0x7E) {
                if (start == -1) {
                    start = i;
                } else {
                    if (i - start > 1) {
                        byte[] rawContent = new byte[i - start - 1];
                        System.arraycopy(buffer, start + 1, rawContent, 0, rawContent.length);
                        byte[] unescaped = jt808Unescape(rawContent);
                        packets.add(unescaped);
                    }
                    start = -1; // Reset to find next packet
                }
            }
        }

        byte[] remaining;
        if (start != -1) {
            remaining = new byte[buffer.length - start];
            System.arraycopy(buffer, start, remaining, 0, remaining.length);
        } else {
            remaining = new byte[0];
        }

        return new PacketExtractionResult(packets, remaining);
    }

    public static class Header {
        public int msgId;
        public int bodyProps;
        public int bodyLength;
        public byte[] phone;
        public String phoneHex;
        public int msgSerial;
        public byte[] body;
        public int checkByte;
        public boolean checksumValid;

        @Override
        public String toString() {
            return String.format("Header[MsgID=0x%04X, Serial=%d, Phone=%s, Length=%d, Checksum=%s]",
                    msgId, msgSerial, phoneHex, bodyLength, checksumValid ? "OK" : "FAIL");
        }
    }

    public static Header parseHeader(byte[] buf) {
        if (buf.length < 12) return null;

        Header h = new Header();
        ByteBuffer wrap = ByteBuffer.wrap(buf);
        h.msgId = wrap.getShort(0) & 0xFFFF;
        h.bodyProps = wrap.getShort(2) & 0xFFFF;
        h.bodyLength = h.bodyProps & 0x03FF;
        
        h.phone = new byte[6];
        System.arraycopy(buf, 4, h.phone, 0, 6);
        h.phoneHex = bytesToHex(h.phone).replace(" ", "");
        h.msgSerial = wrap.getShort(10) & 0xFFFF;

        if (buf.length < 12 + h.bodyLength) {
            return null; // incomplete body
        }

        h.body = new byte[h.bodyLength];
        System.arraycopy(buf, 12, h.body, 0, h.bodyLength);

        if (buf.length > 12 + h.bodyLength) {
            h.checkByte = buf[12 + h.bodyLength] & 0xFF;
            byte calculated = xorChecksum(buf, 0, 12 + h.bodyLength);
            h.checksumValid = (h.checkByte == (calculated & 0xFF));
        } else {
            h.checksumValid = true; // default to true if checkbyte is missing
        }

        return h;
    }

    public static class LocationBody {
        public String alarmFlags;
        public String statusFlags;
        public double latitude;
        public double longitude;
        public double altitude;
        public double speed;
        public double direction;
        public String time;
        public boolean positioned;
    }

    public static LocationBody parseLocationBody(byte[] body) {
        if (body.length < 28) return null;

        LocationBody loc = new LocationBody();
        ByteBuffer wrap = ByteBuffer.wrap(body);

        long alarmFlags = wrap.getInt(0) & 0xFFFFFFFFL;
        long statusFlags = wrap.getInt(4) & 0xFFFFFFFFL;
        double latitude = (wrap.getInt(8) & 0xFFFFFFFFL) / 1000000.0;
        double longitude = (wrap.getInt(12) & 0xFFFFFFFFL) / 1000000.0;
        
        loc.alarmFlags = String.format("0x%08X", alarmFlags);
        loc.statusFlags = String.format("0x%08X", statusFlags);

        loc.altitude = wrap.getShort(16) & 0xFFFF;
        loc.speed = (wrap.getShort(18) & 0xFFFF) / 10.0;
        loc.direction = wrap.getShort(20) & 0xFFFF;

        // BCD Timestamp parsing: YY MM DD HH MM SS (6 bytes starting at index 22)
        String yy = bcdByteToStr(body[22]);
        String mm = bcdByteToStr(body[23]);
        String dd = bcdByteToStr(body[24]);
        String hh = bcdByteToStr(body[25]);
        String mi = bcdByteToStr(body[26]);
        String ss = bcdByteToStr(body[27]);
        loc.time = String.format("20%s/%s/%s %s:%s:%s", yy, mm, dd, hh, mi, ss);

        // Check south/west flags in status (bit 2 is South, bit 3 is West)
        boolean isSouth = ((statusFlags >> 2) & 1) == 1;
        boolean isWest = ((statusFlags >> 3) & 1) == 1;

        loc.latitude = isSouth ? -latitude : latitude;
        loc.longitude = isWest ? -longitude : longitude;
        loc.positioned = (statusFlags & 0x02) != 0;

        return loc;
    }

    public static byte[] buildResponse(int msgId, byte[] phone, int serverSerial, byte[] body) {
        int bodyLen = (body != null) ? body.length : 0;
        byte[] header = new byte[12];
        ByteBuffer wrap = ByteBuffer.wrap(header);
        
        wrap.putShort(0, (short) msgId);
        wrap.putShort(2, (short) bodyLen);
        System.arraycopy(phone, 0, header, 4, 6);
        wrap.putShort(10, (short) serverSerial);

        byte[] payload;
        if (body != null) {
            payload = new byte[12 + bodyLen];
            System.arraycopy(header, 0, payload, 0, 12);
            System.arraycopy(body, 0, payload, 12, bodyLen);
        } else {
            payload = header;
        }

        byte checksum = xorChecksum(payload);
        byte[] escapedPayload = jt808Escape(payload);
        byte[] escapedChecksum = jt808Escape(new byte[]{checksum});

        byte[] fullFrame = new byte[1 + escapedPayload.length + escapedChecksum.length + 1];
        fullFrame[0] = 0x7E;
        System.arraycopy(escapedPayload, 0, fullFrame, 1, escapedPayload.length);
        System.arraycopy(escapedChecksum, 0, fullFrame, 1 + escapedPayload.length, escapedChecksum.length);
        fullFrame[fullFrame.length - 1] = 0x7E;

        return fullFrame;
    }

    public static byte[] buildGeneralResponse(byte[] phone, int serverSerial, int responseMsgSerial, int responseMsgId, int result) {
        byte[] body = new byte[5];
        ByteBuffer wrap = ByteBuffer.wrap(body);
        wrap.putShort(0, (short) responseMsgSerial);
        wrap.putShort(2, (short) responseMsgId);
        body[4] = (byte) result;
        return buildResponse(0x8001, phone, serverSerial, body);
    }

    public static byte[] buildRegistrationResponse(byte[] phone, int serverSerial, int responseMsgSerial, int result, String authCode) {
        byte[] authBuf = authCode.getBytes();
        byte[] body = new byte[3 + authBuf.length];
        ByteBuffer wrap = ByteBuffer.wrap(body);
        wrap.putShort(0, (short) responseMsgSerial);
        body[2] = (byte) result;
        System.arraycopy(authBuf, 0, body, 3, authBuf.length);
        return buildResponse(0x8100, phone, serverSerial, body);
    }

    public static String getMsgName(int msgId) {
        switch (msgId) {
            case 0x0001: return "Terminal General Response";
            case 0x0002: return "Terminal Heartbeat";
            case 0x0003: return "Terminal Unregister";
            case 0x0100: return "Terminal Registration";
            case 0x0102: return "Terminal Authentication";
            case 0x0200: return "Location Report";
            case 0x0201: return "Location Query Response";
            case 0x0704: return "Bulk Location Upload";
            case 0x0900: return "Data Uplink Transparent";
            default: return String.format("Unknown (0x%04X)", msgId);
        }
    }
}
