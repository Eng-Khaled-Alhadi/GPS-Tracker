import 'package:latlong2/latlong.dart';

class Device {
  final String id;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final double direction;
  final String gpsTime;
  final bool positioned;
  final String alarmFlags;
  final String statusFlags;
  final DateTime lastUpdated;
  final List<LatLng> history;
  
  // Custom metadata fields
  final String? name;
  final String? color;
  final String? carType;
  final Map<String, dynamic>? additionalData;

  Device({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.speed,
    required this.direction,
    required this.gpsTime,
    required this.positioned,
    required this.alarmFlags,
    required this.statusFlags,
    required this.lastUpdated,
    required this.history,
    this.name,
    this.color,
    this.carType,
    this.additionalData,
  });

  // Display Name: Show custom name if configured, otherwise ID
  String get displayName => (name != null && name!.trim().isNotEmpty) ? name! : 'ID: $id';

  factory Device.fromJson(Map<String, dynamic> json, List<LatLng> existingHistory) {
    final lat = (json['latitude'] as num).toDouble();
    final lng = (json['longitude'] as num).toDouble();
    final newPoint = LatLng(lat, lng);

    // Keep history unique and within a reasonable size (e.g. last 100 points)
    final updatedHistory = List<LatLng>.from(existingHistory);
    if (updatedHistory.isEmpty || updatedHistory.last != newPoint) {
      updatedHistory.add(newPoint);
      if (updatedHistory.length > 200) {
        updatedHistory.removeAt(0);
      }
    }

    // Safely parse additionalData JSON map
    Map<String, dynamic>? additional;
    if (json['additionalData'] != null) {
      if (json['additionalData'] is Map) {
        additional = Map<String, dynamic>.from(json['additionalData'] as Map);
      }
    }

    return Device(
      id: json['deviceId'].toString(),
      latitude: lat,
      longitude: lng,
      altitude: (json['altitude'] as num).toDouble(),
      speed: (json['speed'] as num).toDouble(),
      direction: (json['direction'] as num).toDouble(),
      gpsTime: json['time'] ?? '',
      positioned: json['positioned'] ?? false,
      alarmFlags: json['alarmFlags'] ?? '0x00000000',
      statusFlags: json['statusFlags'] ?? '0x00000000',
      lastUpdated: DateTime.parse(json['lastUpdated'] ?? DateTime.now().toIso8601String()),
      history: updatedHistory,
      name: json['name']?.toString(),
      color: json['color']?.toString(),
      carType: json['carType']?.toString(),
      additionalData: additional,
    );
  }
}
