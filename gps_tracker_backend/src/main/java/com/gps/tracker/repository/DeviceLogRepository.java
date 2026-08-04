package com.gps.tracker.repository;

import com.gps.tracker.model.DeviceLog;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DeviceLogRepository extends JpaRepository<DeviceLog, Long> {
}
