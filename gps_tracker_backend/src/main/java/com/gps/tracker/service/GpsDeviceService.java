package com.gps.tracker.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.gps.tracker.model.User;
import com.gps.tracker.model.Device;
import com.gps.tracker.model.DeviceHistory;
import com.gps.tracker.model.DeviceLog;
import com.gps.tracker.model.DeviceMetadata;
import com.gps.tracker.repository.DeviceHistoryRepository;
import com.gps.tracker.repository.DeviceLogRepository;
import com.gps.tracker.repository.DeviceMetadataRepository;
import com.gps.tracker.repository.DeviceRepository;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;

import java.io.IOException;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

@Service
public class GpsDeviceService {
    private static final Logger log = LoggerFactory.getLogger(GpsDeviceService.class);
    private static final DateTimeFormatter formatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    @Autowired
    private DeviceRepository deviceRepository;

    @Autowired
    private DeviceHistoryRepository deviceHistoryRepository;

    @Autowired
    private DeviceLogRepository deviceLogRepository;

    @Autowired
    private DeviceMetadataRepository deviceMetadataRepository;

    // In-memory active devices and metadata caches
    private final Map<String, Map<String, Object>> activeDevices = new ConcurrentHashMap<>();
    private final Map<String, DeviceMetadata> deviceMetadataCache = new ConcurrentHashMap<>();

    // In-memory active user sessions
    private final Map<String, User> tokenToUser = new ConcurrentHashMap<>();

    // Keep track of active WebSocket sessions
    private final List<WebSocketSession> wsSessions = new CopyOnWriteArrayList<>();
    private final ObjectMapper objectMapper = new ObjectMapper();

    public String createSessionToken(User user) {
        String token = UUID.randomUUID().toString();
        tokenToUser.put(token, user);
        return token;
    }

    public Optional<User> getUserByToken(String token) {
        if (token == null)
            return Optional.empty();
        return Optional.ofNullable(tokenToUser.get(token));
    }

    public void removeSessionToken(String token) {
        if (token != null) {
            tokenToUser.remove(token);
        }
    }

    @PostConstruct
    public void init() {
        try {
            log.info("Loading device metadata cache from database...");
            List<DeviceMetadata> allMetadata = deviceMetadataRepository.findAll();
            for (DeviceMetadata meta : allMetadata) {
                deviceMetadataCache.put(meta.getDeviceId(), meta);
            }
            log.info("Loaded {} device metadata profiles.", allMetadata.size());
        } catch (Exception e) {
            log.error("Failed to load device metadata cache", e);
        }
    }

    public Map<String, Map<String, Object>> getActiveDevices() {
        return activeDevices;
    }

    public Map<String, DeviceMetadata> getDeviceMetadataCache() {
        return deviceMetadataCache;
    }

    public void addSession(WebSocketSession session, String token) {
        wsSessions.add(session);
        // Send current active devices state
        sendInitialState(session, token);
    }

    public void removeSession(WebSocketSession session) {
        wsSessions.remove(session);
    }

    public void sendInitialState(WebSocketSession session, String token) {
        try {
            Optional<User> userOpt = getUserByToken(token);
            boolean isAdmin = userOpt.isPresent() && "admin".equals(userOpt.get().getRole());

            List<Map<String, Object>> decoratedList = new ArrayList<>();

            if (isAdmin) {
                List<Device> allDbDevices = deviceRepository.findAll();
                Set<String> processedDeviceIds = new HashSet<>();

                // Add active devices first
                for (Map<String, Object> dev : activeDevices.values()) {
                    String devId = (String) dev.get("deviceId");
                    processedDeviceIds.add(devId);

                    Map<String, Object> decorated = new HashMap<>(dev);
                    DeviceMetadata meta = deviceMetadataCache.get(devId);
                    Optional<Device> dbDevOpt = deviceRepository.findByDeviceId(devId);

                    decorated.put("enabled", dbDevOpt.isPresent() ? dbDevOpt.get().getEnabled() : true);
                    if (meta != null) {
                        decorated.put("name", meta.getName());
                        decorated.put("color", meta.getColor());
                        decorated.put("carType", meta.getCarType());
                        decorated.put("additionalData",
                                meta.getAdditionalData() != null
                                        ? objectMapper.readValue(meta.getAdditionalData(), Object.class)
                                        : null);
                    } else {
                        decorated.put("name", null);
                        decorated.put("color", null);
                        decorated.put("carType", null);
                        decorated.put("additionalData", null);
                    }
                    decoratedList.add(decorated);
                }

                // Add database devices that are not active (e.g. disabled or offline)
                for (Device dbDev : allDbDevices) {
                    if (!processedDeviceIds.contains(dbDev.getDeviceId())) {
                        Map<String, Object> dev = new HashMap<>();
                        dev.put("deviceId", dbDev.getDeviceId());
                        dev.put("latitude", dbDev.getLatitude());
                        dev.put("longitude", dbDev.getLongitude());
                        dev.put("altitude", dbDev.getAltitude());
                        dev.put("speed", dbDev.getSpeed());
                        dev.put("direction", dbDev.getDirection());
                        dev.put("time", dbDev.getGpsTime().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")));
                        dev.put("positioned", dbDev.getPositioned());
                        dev.put("alarmFlags", dbDev.getAlarmFlags());
                        dev.put("statusFlags", dbDev.getStatusFlags());
                        dev.put("lastUpdated",
                                dbDev.getLastUpdated() != null
                                        ? dbDev.getLastUpdated()
                                                .format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"))
                                        : LocalDateTime.now().format(formatter));
                        dev.put("enabled", dbDev.getEnabled());

                        DeviceMetadata meta = deviceMetadataCache.get(dbDev.getDeviceId());
                        if (meta != null) {
                            dev.put("name", meta.getName());
                            dev.put("color", meta.getColor());
                            dev.put("carType", meta.getCarType());
                            dev.put("additionalData",
                                    meta.getAdditionalData() != null
                                            ? objectMapper.readValue(meta.getAdditionalData(), Object.class)
                                            : null);
                        } else {
                            dev.put("name", null);
                            dev.put("color", null);
                            dev.put("carType", null);
                            dev.put("additionalData", null);
                        }
                        decoratedList.add(dev);
                    }
                }
            } else {
                // Non-admins only see active enabled devices
                for (Map<String, Object> dev : activeDevices.values()) {
                    String devId = (String) dev.get("deviceId");
                    Map<String, Object> decorated = new HashMap<>(dev);
                    DeviceMetadata meta = deviceMetadataCache.get(devId);

                    decorated.put("enabled", true);
                    if (meta != null) {
                        decorated.put("name", meta.getName());
                        decorated.put("color", meta.getColor());
                        decorated.put("carType", meta.getCarType());
                        decorated.put("additionalData",
                                meta.getAdditionalData() != null
                                        ? objectMapper.readValue(meta.getAdditionalData(), Object.class)
                                        : null);
                    } else {
                        decorated.put("name", null);
                        decorated.put("color", null);
                        decorated.put("carType", null);
                        decorated.put("additionalData", null);
                    }
                    decoratedList.add(decorated);
                }
            }

            Map<String, Object> response = new HashMap<>();
            response.put("type", "devices_state");
            response.put("data", decoratedList);

            session.sendMessage(new TextMessage(objectMapper.writeValueAsString(response)));
        } catch (Exception e) {
            log.error("Error sending initial state to WebSocket client", e);
        }
    }

    public void saveDeviceLocation(String deviceId, double lat, double lon, double alt, double speed, double dir,
            String timeStr, boolean positioned, String alarmFlags, String statusFlags) {
        try {
            LocalDateTime gpsTime;
            try {
                // Parse time formatted as "2026/08/01 15:26:56" or similar
                gpsTime = LocalDateTime.parse(timeStr.replace("/", "-"),
                        DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
            } catch (Exception e) {
                gpsTime = LocalDateTime.now();
            }

            // Check if device already exists
            Optional<Device> deviceOpt = deviceRepository.findByDeviceId(deviceId);
            Device device;
            boolean isEnabled = false;

            if (deviceOpt.isEmpty()) {
                log.warn("Device {} is connecting for the first time. Registering in disabled state.", deviceId);
                device = new Device();
                device.setDeviceId(deviceId);
                device.setEnabled(false);
            } else {
                device = deviceOpt.get();
                isEnabled = device.getEnabled();
            }

            // Always update current position in device record
            device.setLatitude(lat);
            device.setLongitude(lon);
            device.setAltitude(alt);
            device.setSpeed(speed);
            device.setDirection(dir);
            device.setGpsTime(gpsTime);
            device.setPositioned(positioned);
            device.setAlarmFlags(alarmFlags);
            device.setStatusFlags(statusFlags);
            deviceRepository.save(device);

            // Update in-memory active devices
            Map<String, Object> devData = new ConcurrentHashMap<>();
            devData.put("deviceId", deviceId);
            devData.put("latitude", lat);
            devData.put("longitude", lon);
            devData.put("altitude", alt);
            devData.put("speed", speed);
            devData.put("direction", dir);
            devData.put("time", timeStr);
            devData.put("positioned", positioned);
            devData.put("alarmFlags", alarmFlags);
            devData.put("statusFlags", statusFlags);
            devData.put("lastUpdated", LocalDateTime.now().format(formatter));
            activeDevices.put(deviceId, devData);

            // Save history log in DB ONLY if enabled!
            if (isEnabled) {
                DeviceHistory history = new DeviceHistory();
                history.setDeviceId(deviceId);
                history.setLatitude(lat);
                history.setLongitude(lon);
                history.setAltitude(alt);
                history.setSpeed(speed);
                history.setDirection(dir);
                history.setGpsTime(gpsTime);
                history.setPositioned(positioned);
                history.setAlarmFlags(alarmFlags);
                history.setStatusFlags(statusFlags);
                deviceHistoryRepository.save(history);
            }

            // Always broadcast (it will be filtered by broadcastLocation method)
            broadcastLocation(devData);
        } catch (Exception e) {
            log.error("Failed to save location data to DB", e);
        }
    }

    public void logDeviceMessage(String deviceId, int msgId, String msgName, int serialNumber, String bodyHex,
            boolean checksumValid) {
        try {
            DeviceLog dlog = new DeviceLog();
            dlog.setDeviceId(deviceId);
            dlog.setMessageId(String.format("0x%04X", msgId));
            dlog.setMessageName(msgName);
            dlog.setSerialNumber(serialNumber);
            dlog.setBodyHex(bodyHex);
            dlog.setChecksumValid(checksumValid);
            deviceLogRepository.save(dlog);
        } catch (Exception e) {
            log.error("Failed to log device message to DB", e);
        }
    }

    public void updateDeviceMetadata(String deviceId, String name, String color, String carType,
            Object additionalData) {
        try {
            String additionalDataJson = null;
            if (additionalData != null) {
                additionalDataJson = objectMapper.writeValueAsString(additionalData);
            }

            DeviceMetadata meta = deviceMetadataRepository.findById(deviceId).orElse(new DeviceMetadata());
            meta.setDeviceId(deviceId);
            meta.setName(name);
            meta.setColor(color);
            meta.setCarType(carType);
            meta.setAdditionalData(additionalDataJson);
            deviceMetadataRepository.save(meta);

            // Update cache
            deviceMetadataCache.put(deviceId, meta);

            // Broadcast metadata update
            Map<String, Object> updateMsg = new HashMap<>();
            updateMsg.put("type", "metadata_update");
            updateMsg.put("deviceId", deviceId);
            updateMsg.put("name", name);
            updateMsg.put("color", color);
            updateMsg.put("carType", carType);
            updateMsg.put("additionalData", additionalData);
            broadcastMessage(updateMsg);

            // Update in-memory active devices copy
            Map<String, Object> dev = activeDevices.get(deviceId);
            if (dev != null) {
                dev.put("name", name);
                dev.put("color", color);
                dev.put("carType", carType);
                dev.put("additionalData", additionalData);
            }
        } catch (Exception e) {
            log.error("Failed to update device metadata", e);
        }
    }

    private void broadcastLocation(Map<String, Object> devData) {
        try {
            String devId = (String) devData.get("deviceId");
            Optional<Device> dbDevOpt = deviceRepository.findByDeviceId(devId);
            boolean isEnabled = dbDevOpt.isPresent() && dbDevOpt.get().getEnabled();

            Map<String, Object> decorated = new HashMap<>(devData);
            DeviceMetadata meta = deviceMetadataCache.get(devId);

            decorated.put("enabled", isEnabled);
            if (meta != null) {
                decorated.put("name", meta.getName());
                decorated.put("color", meta.getColor());
                decorated.put("carType", meta.getCarType());
                decorated.put("additionalData",
                        meta.getAdditionalData() != null
                                ? objectMapper.readValue(meta.getAdditionalData(), Object.class)
                                : null);
            } else {
                decorated.put("name", null);
                decorated.put("color", null);
                decorated.put("carType", null);
                decorated.put("additionalData", null);
            }

            Map<String, Object> msg = new HashMap<>();
            msg.put("type", "location_update");
            msg.put("data", decorated);

            String json = objectMapper.writeValueAsString(msg);
            TextMessage textMessage = new TextMessage(json);

            for (WebSocketSession session : wsSessions) {
                if (session.isOpen()) {
                    // Extract token and check role
                    String token = null;
                    if (session.getUri() != null && session.getUri().getQuery() != null) {
                        String query = session.getUri().getQuery();
                        for (String param : query.split("&")) {
                            String[] pair = param.split("=");
                            if (pair.length > 1 && "token".equals(pair[0])) {
                                token = pair[1];
                                break;
                            }
                        }
                    }
                    Optional<User> userOpt = getUserByToken(token);
                    boolean isAdmin = userOpt.isPresent() && "admin".equals(userOpt.get().getRole());

                    // Send if device is enabled, OR if user is admin (admin sees all updates)
                    if (isEnabled || isAdmin) {
                        try {
                            session.sendMessage(textMessage);
                        } catch (IOException e) {
                            log.warn("Failed to send message to WS session: {}", session.getId());
                        }
                    }
                }
            }
        } catch (Exception e) {
            log.error("Error preparing location update broadcast", e);
        }
    }

    public void broadcastMessage(Object messagePayload) {
        try {
            String json = objectMapper.writeValueAsString(messagePayload);
            TextMessage textMessage = new TextMessage(json);
            for (WebSocketSession session : wsSessions) {
                if (session.isOpen()) {
                    try {
                        session.sendMessage(textMessage);
                    } catch (IOException e) {
                        log.warn("Failed to send message to WS session: {}", session.getId());
                    }
                }
            }
        } catch (Exception e) {
            log.error("Failed to broadcast message", e);
        }
    }

    public void toggleDeviceEnabled(String deviceId, boolean enabled) {
        try {
            Optional<Device> deviceOpt = deviceRepository.findByDeviceId(deviceId);
            if (deviceOpt.isPresent()) {
                Device device = deviceOpt.get();
                device.setEnabled(enabled);
                deviceRepository.save(device);

                log.info("Device {} enablement toggled to {}", deviceId, enabled);

                // Broadcast refreshed devices list to all connected clients
                for (WebSocketSession session : wsSessions) {
                    // Extract token and send refreshed initial state
                    String token = null;
                    if (session.getUri() != null && session.getUri().getQuery() != null) {
                        String query = session.getUri().getQuery();
                        for (String param : query.split("&")) {
                            String[] pair = param.split("=");
                            if (pair.length > 1 && "token".equals(pair[0])) {
                                token = pair[1];
                                break;
                            }
                        }
                    }
                    sendInitialState(session, token);
                }
            }
        } catch (Exception e) {
            log.error("Failed to toggle device enabled status", e);
        }
    }
}
