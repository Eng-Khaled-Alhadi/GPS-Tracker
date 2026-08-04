package com.gps.tracker.repository;

import com.gps.tracker.model.Device;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import java.util.List;
import java.util.Optional;

public interface DeviceRepository extends JpaRepository<Device, Long> {
    Optional<Device> findByDeviceId(String deviceId);

    @Query(value = "SELECT DISTINCT device_id FROM devices UNION SELECT DISTINCT device_id FROM device_history", nativeQuery = true)
    List<String> findDistinctDeviceIds();
}
