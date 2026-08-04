package com.gps.tracker.repository;

import com.gps.tracker.model.DeviceMetadata;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DeviceMetadataRepository extends JpaRepository<DeviceMetadata, String> {
}
