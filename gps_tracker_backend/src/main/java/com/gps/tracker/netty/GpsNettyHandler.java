package com.gps.tracker.netty;

import com.gps.tracker.service.GpsDeviceService;
import com.gps.tracker.util.Jt808Helper;
import io.netty.buffer.ByteBuf;
import io.netty.buffer.Unpooled;
import io.netty.channel.ChannelHandlerContext;
import io.netty.channel.ChannelInboundHandlerAdapter;
import io.netty.util.AttributeKey;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.net.InetSocketAddress;

public class GpsNettyHandler extends ChannelInboundHandlerAdapter {
    private static final Logger log = LoggerFactory.getLogger(GpsNettyHandler.class);
    private static final AttributeKey<byte[]> INCOMPLETE_BUFFER_KEY = AttributeKey.valueOf("incompleteBuffer");
    
    private final GpsDeviceService gpsDeviceService;
    private int serverSerial = 0;

    public GpsNettyHandler(GpsDeviceService gpsDeviceService) {
        this.gpsDeviceService = gpsDeviceService;
    }

    @Override
    public void channelActive(ChannelHandlerContext ctx) throws Exception {
        InetSocketAddress remoteAddress = (InetSocketAddress) ctx.channel().remoteAddress();
        log.info("JT808 Client connected: {}:{}", remoteAddress.getHostString(), remoteAddress.getPort());
        ctx.channel().attr(INCOMPLETE_BUFFER_KEY).set(new byte[0]);
    }

    @Override
    public void channelRead(ChannelHandlerContext ctx, Object msg) throws Exception {
        ByteBuf in = (ByteBuf) msg;
        try {
            int readableBytes = in.readableBytes();
            byte[] incoming = new byte[readableBytes];
            in.readBytes(incoming);

            InetSocketAddress remoteAddress = (InetSocketAddress) ctx.channel().remoteAddress();
            String clientAddress = remoteAddress.getHostString() + ":" + remoteAddress.getPort();

            // Retrieve incomplete buffer from channel attributes
            byte[] incomplete = ctx.channel().attr(INCOMPLETE_BUFFER_KEY).get();
            if (incomplete == null) {
                incomplete = new byte[0];
            }

            // Concatenate buffers
            byte[] total = new byte[incomplete.length + incoming.length];
            System.arraycopy(incomplete, 0, total, 0, incomplete.length);
            System.arraycopy(incoming, 0, total, incomplete.length, incoming.length);

            // Log raw hex data (optional log)
            log.debug("Raw data from {}: {}", clientAddress, Jt808Helper.bytesToHex(incoming));

            // Extract packets
            Jt808Helper.PacketExtractionResult extraction = Jt808Helper.extractPackets(total);
            ctx.channel().attr(INCOMPLETE_BUFFER_KEY).set(extraction.remaining);

            // Process each packet
            for (byte[] packet : extraction.packets) {
                Jt808Helper.Header header = Jt808Helper.parseHeader(packet);
                if (header == null) {
                    log.warn("Could not parse packet header from {}", clientAddress);
                    continue;
                }

                String msgName = Jt808Helper.getMsgName(header.msgId);
                String bodyHex = Jt808Helper.bytesToHex(header.body);
                log.info("Message: {} | Serial: {} | Phone: {} | Checksum: {}", 
                        msgName, header.msgSerial, header.phoneHex, header.checksumValid ? "OK" : "FAIL");

                // Log device message in database
                gpsDeviceService.logDeviceMessage(header.phoneHex, header.msgId, msgName, header.msgSerial, bodyHex, header.checksumValid);

                byte[] response = null;
                serverSerial++;

                switch (header.msgId) {
                    case 0x0100: // Terminal Registration
                        log.info(">>> Terminal Registration from {}", header.phoneHex);
                        response = Jt808Helper.buildRegistrationResponse(
                                header.phone,
                                serverSerial,
                                header.msgSerial,
                                0, // 0 = success
                                "OK" // Auth code
                        );
                        break;

                    case 0x0102: // Terminal Authentication
                        log.info(">>> Terminal Authentication from {}", header.phoneHex);
                        response = Jt808Helper.buildGeneralResponse(
                                header.phone, serverSerial,
                                header.msgSerial, header.msgId, 0
                        );
                        break;

                    case 0x0002: // Terminal Heartbeat
                        log.info(">>> Heartbeat from {}", header.phoneHex);
                        response = Jt808Helper.buildGeneralResponse(
                                header.phone, serverSerial,
                                header.msgSerial, header.msgId, 0
                        );
                        break;

                    case 0x0003: // Terminal Unregister (treating as heartbeat/general ACK)
                        log.info(">>> Unregister/Heartbeat (0x0003) from {}", header.phoneHex);
                        response = Jt808Helper.buildGeneralResponse(
                                header.phone, serverSerial,
                                header.msgSerial, header.msgId, 0
                        );
                        break;

                    case 0x0200: // Location Report
                        Jt808Helper.LocationBody loc = Jt808Helper.parseLocationBody(header.body);
                        if (loc != null) {
                            log.info(">>> Location: Lat={}, Lon={}, Speed={}km/h, Alt={}m, Time={}, GPS={}", 
                                    loc.latitude, loc.longitude, loc.speed, loc.altitude, loc.time, loc.positioned ? "YES" : "NO");

                            gpsDeviceService.saveDeviceLocation(
                                    header.phoneHex,
                                    loc.latitude,
                                    loc.longitude,
                                    loc.altitude,
                                    loc.speed,
                                    loc.direction,
                                    loc.time,
                                    loc.positioned,
                                    loc.alarmFlags,
                                    loc.statusFlags
                            );
                        }
                        response = Jt808Helper.buildGeneralResponse(
                                header.phone, serverSerial,
                                header.msgSerial, header.msgId, 0
                        );
                        break;

                    case 0x0001: // Terminal General Response
                        log.info(">>> Device ACK received");
                        break;

                    default:
                        log.info(">>> Unknown message 0x{} — sending general ACK", Integer.toHexString(header.msgId));
                        response = Jt808Helper.buildGeneralResponse(
                                header.phone, serverSerial,
                                header.msgSerial, header.msgId, 0
                        );
                        break;
                }

                if (response != null && ctx.channel().isActive()) {
                    ctx.writeAndFlush(Unpooled.copiedBuffer(response));
                    log.debug("<<< Sent response: {}", Jt808Helper.bytesToHex(response));
                }
            }
        } finally {
            in.release();
        }
    }

    @Override
    public void exceptionCaught(ChannelHandlerContext ctx, Throwable cause) throws Exception {
        log.error("Socket exception: {}", cause.getMessage());
        ctx.close();
    }

    @Override
    public void channelInactive(ChannelHandlerContext ctx) throws Exception {
        InetSocketAddress remoteAddress = (InetSocketAddress) ctx.channel().remoteAddress();
        log.info("Client disconnected: {}:{}", remoteAddress.getHostString(), remoteAddress.getPort());
    }
}
