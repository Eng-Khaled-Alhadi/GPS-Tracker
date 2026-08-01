import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:latlong2/latlong.dart';
import '../models/device.dart';

class GPSProvider extends ChangeNotifier {
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _serverAddress = 'ws://176.45.55.56:3000';
  String _currentRole = 'viewer';
  String _currentUsername = 'Guest';

  // Tracking devices
  final Map<String, Device> _devices = {};
  String? _selectedDeviceId;
  bool _autoFollow = true;
  Timer? _reconnectTimer;

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get serverAddress => _serverAddress;
  String get currentRole => _currentRole;
  String get currentUsername => _currentUsername;
  List<Device> get devicesList => _devices.values.toList();
  Map<String, Device> get devicesMap => _devices;
  String? get selectedDeviceId => _selectedDeviceId;
  bool get autoFollow => _autoFollow;

  Device? get selectedDevice {
    if (_selectedDeviceId != null && _devices.containsKey(_selectedDeviceId)) {
      return _devices[_selectedDeviceId];
    }
    return null;
  }

  void initializeSession({
    required String role,
    required String username,
    required String serverUrl,
  }) {
    _currentRole = role;
    _currentUsername = username;
    _serverAddress = serverUrl;
    connectWebSocket();
  }

  void connectWebSocket() {
    if (_isConnecting || _isConnected) return;

    _isConnecting = true;
    notifyListeners();

    try {
      final uri = Uri.parse(_serverAddress);
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (message) => _handleIncomingMessage(message),
        onError: (err) {
          debugPrint('WebSocket Connection Error: $err');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('WebSocket Connection Closed');
          _handleDisconnect();
        },
      );

      _isConnected = true;
      _isConnecting = false;
      notifyListeners();
    } catch (e) {
      debugPrint('WS Handshake Exception: $e');
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    notifyListeners();

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isConnected && !_isConnecting) {
        connectWebSocket();
      }
    });
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      final parsed = jsonDecode(message) as Map<String, dynamic>;
      final type = parsed['type'];
      final data = parsed['data'];

      if (type == 'devices_state' && data is List) {
        for (final item in data) {
          final devId = item['deviceId'].toString();
          final oldHistory = _devices[devId]?.history ?? [];
          _devices[devId] = Device.fromJson(item, oldHistory);
        }
        _setDefaultSelection();
        notifyListeners();
      } else if (type == 'location_update' && data is Map) {
        final devId = data['deviceId'].toString();
        final oldHistory = _devices[devId]?.history ?? [];
        final updatedDevice = Device.fromJson(
          data as Map<String, dynamic>,
          oldHistory,
        );
        _devices[devId] = updatedDevice;

        _setDefaultSelection();
        notifyListeners();
      } else if (type == 'metadata_update') {
        final devId = parsed['deviceId'].toString();
        if (_devices.containsKey(devId)) {
          final dev = _devices[devId]!;
          _devices[devId] = Device(
            id: dev.id,
            latitude: dev.latitude,
            longitude: dev.longitude,
            altitude: dev.altitude,
            speed: dev.speed,
            direction: dev.direction,
            gpsTime: dev.gpsTime,
            positioned: dev.positioned,
            alarmFlags: dev.alarmFlags,
            statusFlags: dev.statusFlags,
            lastUpdated: dev.lastUpdated,
            history: dev.history,
            name: parsed['name']?.toString(),
            color: parsed['color']?.toString(),
            carType: parsed['carType']?.toString(),
            additionalData: parsed['additionalData'] != null ? Map<String, dynamic>.from(parsed['additionalData'] as Map) : null,
          );
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error parsing WebSocket provider message: $e');
    }
  }

  void _setDefaultSelection() {
    if (_selectedDeviceId == null && _devices.isNotEmpty) {
      _selectedDeviceId = _devices.keys.first;
    }
  }

  void selectDevice(String deviceId) {
    _selectedDeviceId = deviceId;
    notifyListeners();
  }

  void setAutoFollow(bool value) {
    _autoFollow = value;
    notifyListeners();
  }

  void updateDeviceMetadata({
    required String deviceId,
    required String name,
    required String color,
    required String carType,
    required Map<String, dynamic> additionalData,
  }) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode({
        'type': 'update_device_metadata',
        'deviceId': deviceId,
        'name': name,
        'color': color,
        'carType': carType,
        'additionalData': additionalData,
        'role': _currentRole,
      }));
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
