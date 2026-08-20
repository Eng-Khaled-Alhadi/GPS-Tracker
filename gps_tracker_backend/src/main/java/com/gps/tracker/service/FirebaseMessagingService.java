package com.gps.tracker.service;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.*;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;

@Service
public class FirebaseMessagingService {

    private static final Logger log = LoggerFactory.getLogger(FirebaseMessagingService.class);

    // Topic requested by user
    public static final String OVERSPEED_TOPIC = "speeLimit";

    @Value("${firebase.credentials.path:firebase-service-account.json}")
    private String credentialsPath;

    private boolean initialized = false;

    @PostConstruct
    public void initialize() {
        try {
            if (!FirebaseApp.getApps().isEmpty()) {
                initialized = true;
                log.info("FirebaseApp is already initialized.");
                return;
            }

            InputStream serviceAccountStream = null;

            // 1. Try direct file path (relative or absolute)
            File file = new File(credentialsPath);
            if (file.exists()) {
                serviceAccountStream = new FileInputStream(file);
                log.info("Found Firebase credentials file at: {}", file.getAbsolutePath());
            }

            // 2. Try classpath resource
            if (serviceAccountStream == null) {
                try {
                    ClassPathResource resource = new ClassPathResource(credentialsPath);
                    if (resource.exists()) {
                        serviceAccountStream = resource.getInputStream();
                        log.info("Found Firebase credentials in classpath: {}", credentialsPath);
                    }
                } catch (Exception ignored) {
                }
            }

            // 3. Try default application credentials fallback
            FirebaseOptions options;
            if (serviceAccountStream != null) {
                options = FirebaseOptions.builder()
                        .setCredentials(GoogleCredentials.fromStream(serviceAccountStream))
                        .build();
            } else {
                log.warn("No firebase credentials file found at '{}'. Checking Google Application Default Credentials...", credentialsPath);
                try {
                    options = FirebaseOptions.builder()
                            .setCredentials(GoogleCredentials.getApplicationDefault())
                            .build();
                } catch (Exception e) {
                    log.warn("Firebase Admin SDK not initialized: No valid credentials found. To enable push notifications, place 'firebase-service-account.json' in the backend root directory or configure 'firebase.credentials.path'.");
                    return;
                }
            }

            FirebaseApp.initializeApp(options);
            initialized = true;
            log.info("Firebase Admin SDK successfully initialized for push notifications (Topic: {})", OVERSPEED_TOPIC);
        } catch (Exception e) {
            log.error("Failed to initialize Firebase Admin SDK: {}", e.getMessage());
        }
    }

    /**
     * Sends an overspeed push notification to the topic 'speeLimit' for Web, iOS, and Android.
     */
    public void sendOverspeedNotification(String deviceName, String deviceId, double speed, double limit, double lat, double lon) {
        if (!initialized) {
            log.debug("Firebase is not initialized. Skipping push notification to topic '{}'.", OVERSPEED_TOPIC);
            return;
        }

        try {
            String title = "⚠️ Speed Limit Alert: " + deviceName;
            String body = String.format("%s is driving at %.1f km/h (Limit: %.0f km/h)", deviceName, speed, limit);

            Map<String, String> data = new HashMap<>();
            data.put("type", "overspeed");
            data.put("deviceId", deviceId);
            data.put("deviceName", deviceName);
            data.put("speed", String.format("%.1f", speed));
            data.put("limit", String.format("%.0f", limit));
            data.put("latitude", String.valueOf(lat));
            data.put("longitude", String.valueOf(lon));
            data.put("timestamp", String.valueOf(System.currentTimeMillis()));
            data.put("click_action", "FLUTTER_NOTIFICATION_CLICK");

            // Build multiplatform message targeted at topic 'speeLimit'
            Message message = Message.builder()
                    .setTopic(OVERSPEED_TOPIC)
                    .setNotification(Notification.builder()
                            .setTitle(title)
                            .setBody(body)
                            .build())
                    .putAllData(data)
                    // Android-specific configuration
                    .setAndroidConfig(AndroidConfig.builder()
                            .setPriority(AndroidConfig.Priority.HIGH)
                            .setNotification(AndroidNotification.builder()
                                    .setTitle(title)
                                    .setBody(body)
                                    .setIcon("ic_launcher")
                                    .setColor("#EF4444")
                                    .setSound("default")
                                    .setChannelId("overspeed_alerts")
                                    .build())
                            .build())
                    // iOS / APNs configuration
                    .setApnsConfig(ApnsConfig.builder()
                            .setAps(Aps.builder()
                                    .setSound("default")
                                    .setBadge(1)
                                    .setContentAvailable(true)
                                    .build())
                            .build())
                    // Webpush configuration
                    .setWebpushConfig(WebpushConfig.builder()
                            .putHeader("Urgency", "high")
                            .setNotification(WebpushNotification.builder()
                                    .setTitle(title)
                                    .setBody(body)
                                    .setIcon("/favicon.png")
                                    .setBadge("/favicon.png")
                                    .build())
                            .build())
                    .build();

            // Send asynchronously to avoid blocking the GPS telemetry ingestion thread
            FirebaseMessaging.getInstance().sendAsync(message);
            log.info("Successfully dispatched Firebase push notification to topic '{}' for device '{}' (Speed: {} km/h)",
                    OVERSPEED_TOPIC, deviceName, speed);

        } catch (Exception e) {
            log.error("Error sending Firebase overspeed push notification", e);
        }
    }

    public boolean isInitialized() {
        return initialized;
    }
}
