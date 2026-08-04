package com.gps.tracker.repository;

import com.gps.tracker.model.DeviceHistory;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.List;

public interface DeviceHistoryRepository extends JpaRepository<DeviceHistory, Long> {
    @Query(value = "SELECT * FROM device_history WHERE device_id = :deviceId AND DATE(gps_time) = :date ORDER BY gps_time ASC", nativeQuery = true)
    List<DeviceHistory> findHistory(@Param("deviceId") String deviceId, @Param("date") String date);
}
