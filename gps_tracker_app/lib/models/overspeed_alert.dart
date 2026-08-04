class OverspeedAlert {
  final String id;
  final String deviceId;
  final String deviceName;
  final double speed;
  final double limit;
  final DateTime timestamp;
  bool isRead;

  OverspeedAlert({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.speed,
    required this.limit,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'speed': speed,
      'limit': limit,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
    };
  }

  factory OverspeedAlert.fromJson(Map<String, dynamic> json) {
    return OverspeedAlert(
      id: json['id'] as String,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      speed: (json['speed'] as num).toDouble(),
      limit: (json['limit'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['isRead'] as bool? ?? false,
    );
  }
}
