package com.gps.tracker.websocket;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.gps.tracker.model.DeviceHistory;
import com.gps.tracker.model.User;
import com.gps.tracker.repository.DeviceHistoryRepository;
import com.gps.tracker.repository.DeviceRepository;
import com.gps.tracker.repository.UserRepository;
import com.gps.tracker.service.GpsDeviceService;
import com.gps.tracker.util.HashUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketSession;
import org.springframework.web.socket.handler.TextWebSocketHandler;

import java.io.IOException;
import java.util.*;

@Component
public class GpsWebSocketHandler extends TextWebSocketHandler {
    private static final Logger log = LoggerFactory.getLogger(GpsWebSocketHandler.class);
    private final ObjectMapper objectMapper = new ObjectMapper()
            .registerModule(new JavaTimeModule())
            .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    @Autowired
    private GpsDeviceService gpsDeviceService;

    @Autowired
    private DeviceRepository deviceRepository;

    @Autowired
    private DeviceHistoryRepository deviceHistoryRepository;

    @Autowired
    private UserRepository userRepository;

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        log.info("WebSocket client connected from {}", session.getRemoteAddress());

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

        gpsDeviceService.addSession(session, token);
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) throws Exception {
        log.info("WebSocket client disconnected: {}", session.getRemoteAddress());
        gpsDeviceService.removeSession(session);
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        try {
            Map<String, Object> request = objectMapper.readValue(message.getPayload(), Map.class);
            String type = (String) request.get("type");
            if (type == null)
                return;

            log.info("Received WebSocket message type: {}", type);

            if ("login".equals(type)) {
                handleLogin(session, request);
                return;
            }

            // Token authentication check for all other endpoints
            String token = (String) request.get("token");
            Optional<User> userOpt = gpsDeviceService.getUserByToken(token);
            if (userOpt.isEmpty()) {
                Map<String, Object> errResponse = new HashMap<>();
                errResponse.put("type", "unauthorized_response");
                errResponse.put("success", false);
                errResponse.put("message", "Unauthorized: Invalid or missing authentication token.");
                sendResponse(session, errResponse);
                return;
            }

            User user = userOpt.get();
            String userRole = user.getRole();

            switch (type) {
                case "get_devices":
                    handleGetDevices(session);
                    break;
                case "get_history":
                    handleGetHistory(session, request);
                    break;
                case "get_users":
                    handleGetUsers(session, userRole);
                    break;
                case "create_user":
                    handleCreateUser(session, request, userRole);
                    break;
                case "delete_user":
                    handleDeleteUser(session, request, userRole);
                    break;
                case "update_device_metadata":
                    handleUpdateDeviceMetadata(session, request, userRole);
                    break;
                case "toggle_device_enabled":
                    handleToggleDeviceEnabled(session, request, userRole);
                    break;
                case "set_speed_limit":
                    handleSetSpeedLimit(session, request, userRole);
                    break;
                case "fetch_devices":
                    gpsDeviceService.sendInitialState(session, token);
                    break;
                default:
                    log.warn("Unknown message type: {}", type);
            }
        } catch (Exception e) {
            log.error("Error handling WebSocket text message", e);
        }
    }

    private void handleSetSpeedLimit(WebSocketSession session, Map<String, Object> request, String userRole) throws IOException {
        if (!"admin".equals(userRole)) {
            Map<String, Object> response = new HashMap<>();
            response.put("type", "error");
            response.put("message", "Unauthorized: Only admins can change the speed limit.");
            sendResponse(session, response);
            return;
        }

        Object limitObj = request.get("limit");
        if (limitObj != null) {
            try {
                double limit = Double.parseDouble(limitObj.toString());
                gpsDeviceService.setSpeedLimitThreshold(limit);
                Map<String, Object> response = new HashMap<>();
                response.put("type", "speed_limit_updated");
                response.put("limit", limit);
                sendResponse(session, response);
            } catch (NumberFormatException e) {
                log.error("Invalid speed limit format: {}", limitObj);
            }
        }
    }

    private void handleGetDevices(WebSocketSession session) throws IOException {
        List<String> devices = deviceRepository.findDistinctDeviceIds();
        Map<String, Object> response = new HashMap<>();
        response.put("type", "devices_list_response");
        response.put("devices", devices);
        sendResponse(session, response);
    }

    private void handleGetHistory(WebSocketSession session, Map<String, Object> request) throws IOException {
        String deviceId = (String) request.get("deviceId");
        String date = (String) request.get("date"); // Expects YYYY-MM-DD

        List<DeviceHistory> history = new ArrayList<>();
        if (deviceId != null && date != null) {
            history = deviceHistoryRepository.findHistory(deviceId, date);
        }

        Map<String, Object> response = new HashMap<>();
        response.put("type", "history_response");
        response.put("deviceId", deviceId);
        response.put("date", date);
        response.put("history", history);
        sendResponse(session, response);
    }

    private void handleLogin(WebSocketSession session, Map<String, Object> request) throws IOException {
        String username = (String) request.get("username");
        String password = (String) request.get("password");

        Map<String, Object> response = new HashMap<>();
        response.put("type", "login_response");

        if (username == null || password == null) {
            response.put("success", false);
            response.put("message", "Username and password are required");
            sendResponse(session, response);
            return;
        }

        String passHash = HashUtil.sha256(password);
        Optional<User> userOpt = userRepository.findByUsername(username);
        User matchedUser = null;

        if (userOpt.isPresent()) {
            User user = userOpt.get();
            if (user.getPasswordHash().equals(passHash)) {
                matchedUser = user;
            }
        }

        // Fallback for default mock user (always available as backup)
        if (matchedUser == null && "admin".equals(username) && "admin123".equals(password)) {
            matchedUser = new User();
            matchedUser.setUsername("admin");
            matchedUser.setRole("admin");
            matchedUser.setPasswordHash(passHash);
        }

        if (matchedUser != null) {
            String token = gpsDeviceService.createSessionToken(matchedUser);
            response.put("success", true);
            response.put("role", matchedUser.getRole());
            response.put("username", matchedUser.getUsername());
            response.put("token", token); // Return token to client
        } else {
            response.put("success", false);
            response.put("message", "Invalid username or password");
        }
        sendResponse(session, response);
    }

    private void handleGetUsers(WebSocketSession session, String userRole) throws IOException {
        Map<String, Object> response = new HashMap<>();
        response.put("type", "users_list_response");

        if (!"admin".equals(userRole)) {
            response.put("success", false);
            response.put("message", "Unauthorized");
        } else {
            List<User> users = userRepository.findAll();
            response.put("success", true);
            response.put("users", users);
        }
        sendResponse(session, response);
    }

    private void handleCreateUser(WebSocketSession session, Map<String, Object> request, String userRole)
            throws IOException {
        String username = (String) request.get("username");
        String password = (String) request.get("password");
        String newUserRole = (String) request.get("userRole");

        Map<String, Object> response = new HashMap<>();
        response.put("type", "create_user_response");

        if (!"admin".equals(userRole)) {
            response.put("success", false);
            response.put("message", "Unauthorized");
        } else if (username == null || password == null || newUserRole == null) {
            response.put("success", false);
            response.put("message", "Missing required fields");
        } else if (userRepository.existsByUsername(username)) {
            response.put("success", false);
            response.put("message", "Username already exists");
        } else {
            User user = new User();
            user.setUsername(username);
            user.setPasswordHash(HashUtil.sha256(password));
            user.setRole(newUserRole);
            userRepository.save(user);

            response.put("success", true);
            response.put("message", "User created successfully");
        }
        sendResponse(session, response);
    }

    private void handleDeleteUser(WebSocketSession session, Map<String, Object> request, String userRole)
            throws IOException {
        Number userIdNum = (Number) request.get("userId");

        Map<String, Object> response = new HashMap<>();
        response.put("type", "delete_user_response");

        if (!"admin".equals(userRole)) {
            response.put("success", false);
            response.put("message", "Unauthorized");
        } else if (userIdNum == null) {
            response.put("success", false);
            response.put("message", "Missing userId");
        } else {
            userRepository.deleteById(userIdNum.longValue());
            response.put("success", true);
            response.put("message", "User deleted successfully");
        }
        sendResponse(session, response);
    }

    private void handleUpdateDeviceMetadata(WebSocketSession session, Map<String, Object> request, String userRole)
            throws IOException {
        String deviceId = (String) request.get("deviceId");
        String name = (String) request.get("name");
        String color = (String) request.get("color");
        String carType = (String) request.get("carType");
        Object additionalData = request.get("additionalData");

        if (!"admin".equals(userRole) && !"editor".equals(userRole)) {
            Map<String, Object> response = new HashMap<>();
            response.put("type", "update_device_metadata_response");
            response.put("success", false);
            response.put("message", "Unauthorized: Viewer or guest roles cannot modify metadata.");
            sendResponse(session, response);
        } else {
            gpsDeviceService.updateDeviceMetadata(deviceId, name, color, carType, additionalData);
        }
    }

    private void handleToggleDeviceEnabled(WebSocketSession session, Map<String, Object> request, String userRole) throws IOException {
        String deviceId = (String) request.get("deviceId");
        Boolean enabled = (Boolean) request.get("enabled");

        if (!"admin".equals(userRole)) {
            Map<String, Object> response = new HashMap<>();
            response.put("type", "toggle_device_enabled_response");
            response.put("success", false);
            response.put("message", "Unauthorized: Only admins can enable/disable devices.");
            sendResponse(session, response);
        } else if (deviceId == null || enabled == null) {
            Map<String, Object> response = new HashMap<>();
            response.put("type", "toggle_device_enabled_response");
            response.put("success", false);
            response.put("message", "Missing required fields.");
            sendResponse(session, response);
        } else {
            gpsDeviceService.toggleDeviceEnabled(deviceId, enabled);
        }
    }

    private void sendResponse(WebSocketSession session, Object response) throws IOException {
        if (session.isOpen()) {
            session.sendMessage(new TextMessage(objectMapper.writeValueAsString(response)));
        }
    }
}
