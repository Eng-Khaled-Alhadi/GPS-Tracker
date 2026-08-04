package com.gps.tracker.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "device_logs", indexes = {
    @Index(name = "idx_log_device_id", columnList = "device_id")
})
public class DeviceLog {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "device_id", nullable = false, length = 50)
    private String deviceId;

    @Column(name = "message_id", nullable = false, length = 10)
    private String messageId;

    @Column(name = "message_name", nullable = false, length = 100)
    private String messageName;

    @Column(name = "serial_number", nullable = false)
    private Integer serialNumber;

    @Column(name = "body_hex", columnDefinition = "TEXT")
    private String bodyHex;

    @Column(name = "checksum_valid", nullable = false)
    private Boolean checksumValid;

    @Column(name = "received_at", insertable = false, updatable = false, columnDefinition = "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
    private LocalDateTime receivedAt;

    // Getters and Setters
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getDeviceId() { return deviceId; }
    public void setDeviceId(String deviceId) { this.deviceId = deviceId; }

    public String getMessageId() { return messageId; }
    public void setMessageId(String messageId) { this.messageId = messageId; }

    public String getMessageName() { return messageName; }
    public void setMessageName(String messageName) { this.messageName = messageName; }

    public Integer getSerialNumber() { return serialNumber; }
    public void setSerialNumber(Integer serialNumber) { this.serialNumber = serialNumber; }

    public String getBodyHex() { return bodyHex; }
    public void setBodyHex(String bodyHex) { this.bodyHex = bodyHex; }

    public Boolean getChecksumValid() { return checksumValid; }
    public void setChecksumValid(Boolean checksumValid) { this.checksumValid = checksumValid; }

    public LocalDateTime getReceivedAt() { return receivedAt; }
    public void setReceivedAt(LocalDateTime receivedAt) { this.receivedAt = receivedAt; }
}
