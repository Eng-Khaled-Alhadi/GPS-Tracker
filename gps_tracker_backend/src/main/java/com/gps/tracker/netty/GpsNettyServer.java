package com.gps.tracker.netty;

import com.gps.tracker.service.GpsDeviceService;
import io.netty.bootstrap.ServerBootstrap;
import io.netty.channel.ChannelFuture;
import io.netty.channel.ChannelInitializer;
import io.netty.channel.EventLoopGroup;
import io.netty.channel.nio.NioEventLoopGroup;
import io.netty.channel.socket.SocketChannel;
import io.netty.channel.socket.nio.NioServerSocketChannel;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class GpsNettyServer {
    private static final Logger log = LoggerFactory.getLogger(GpsNettyServer.class);

    @Value("${gps.netty.port:8000}")
    private int port;

    @Autowired
    private GpsDeviceService gpsDeviceService;

    private EventLoopGroup bossGroup;
    private EventLoopGroup workerGroup;
    private ChannelFuture serverChannelFuture;

    @PostConstruct
    public void start() {
        new Thread(() -> {
            log.info("Starting Netty TCP Server on port {}...", port);
            bossGroup = new NioEventLoopGroup(1);
            workerGroup = new NioEventLoopGroup();
            try {
                ServerBootstrap b = new ServerBootstrap();
                b.group(bossGroup, workerGroup)
                 .channel(NioServerSocketChannel.class)
                 .childHandler(new ChannelInitializer<SocketChannel>() {
                     @Override
                     protected void initChannel(SocketChannel ch) throws Exception {
                         ch.pipeline().addLast(new GpsNettyHandler(gpsDeviceService));
                     }
                 });

                serverChannelFuture = b.bind(port).sync();
                log.info("Netty TCP Server is running on port {}.", port);
                serverChannelFuture.channel().closeFuture().sync();
            } catch (InterruptedException e) {
                log.error("Netty TCP Server interrupted", e);
                Thread.currentThread().interrupt();
            } catch (Exception e) {
                log.error("Failed to start Netty TCP Server", e);
            } finally {
                stop();
            }
        }, "netty-server-thread").start();
    }

    @PreDestroy
    public void stop() {
        log.info("Stopping Netty TCP Server...");
        if (bossGroup != null) {
            bossGroup.shutdownGracefully();
        }
        if (workerGroup != null) {
            workerGroup.shutdownGracefully();
        }
        log.info("Netty TCP Server stopped.");
    }
}
