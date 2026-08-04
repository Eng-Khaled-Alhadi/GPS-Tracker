package com.gps.tracker.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "device_history", indexes = {
    @Index(name = "idx_device_id", columnList = "device_id"),
    @Index(name = "idx_gps_time", columnList = "gps_time")
})
public class DeviceHistory {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "device_id", nullable = false, length = 50)
    private String deviceId;

    @Column(nullable = false)
    private Double latitude;

    @Column(nullable = false)
    private Double longitude;

    @Column(nullable = false)
    private Double altitude;

    @Column(nullable = false)
    private Double speed;

    @Column(nullable = false)
    private Double direction;

    @Column(name = "gps_time", nullable = false)
    private LocalDateTime gpsTime;

    @Column(nullable = false)
    private Boolean positioned;

    @Column(name = "alarm_flags", nullable = false, length = 20)
    private String alarmFlags;

    @Column(name = "status_flags", nullable = false, length = 20)
    private String statusFlags;

    @Column(name = "received_at", insertable = false, updatable = false, columnDefinition = "TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
    private LocalDateTime receivedAt;

    // Getters and Setters
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getDeviceId() { return deviceId; }
    public void setDeviceId(String deviceId) { this.deviceId = deviceId; }

    public Double getLatitude() { return latitude; }
    public void setLatitude(Double latitude) { this.latitude = latitude; }

    public Double getLongitude() { return longitude; }
    public void setLongitude(Double longitude) { this.longitude = longitude; }

    public Double getAltitude() { return altitude; }
    public void setAltitude(Double altitude) { this.altitude = altitude; }

    public Double getSpeed() { return speed; }
    public void setSpeed(Double speed) { this.speed = speed; }

    public Double getDirection() { return direction; }
    public void setDirection(Double direction) { this.direction = direction; }

    public LocalDateTime getGpsTime() { return gpsTime; }
    public void setGpsTime(LocalDateTime gpsTime) { this.gpsTime = gpsTime; }

    public Boolean getPositioned() { return positioned; }
    public void setPositioned(Boolean positioned) { this.positioned = positioned; }

    public String getAlarmFlags() { return alarmFlags; }
    public void setAlarmFlags(String alarmFlags) { this.alarmFlags = alarmFlags; }

    public String getStatusFlags() { return statusFlags; }
    public void setStatusFlags(String statusFlags) { this.statusFlags = statusFlags; }

    public LocalDateTime getReceivedAt() { return receivedAt; }
    public void setReceivedAt(LocalDateTime receivedAt) { this.receivedAt = receivedAt; }
}
