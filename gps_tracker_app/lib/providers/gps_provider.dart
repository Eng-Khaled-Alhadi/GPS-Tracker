import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/device.dart';
import '../models/overspeed_alert.dart';

String get defaultAddress {
  if (!kDebugMode) {
    return 'wss://tracking.qutma.com/ws';
  }
  const envHost = String.fromEnvironment('SERVER_HOST');
  if (envHost.isNotEmpty) {
    if (envHost.startsWith('ws://') || envHost.startsWith('wss://')) {
      return envHost;
    }
    return envHost.contains(':') ? 'ws://$envHost/ws' : 'wss://$envHost/ws';
  }

  if (kIsWeb) {
    final uri = Uri.base;
    final isLocal =
        uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '0.0.0.0' ||
        uri.host.isEmpty;

    if (kDebugMode || isLocal) {
      final host = uri.host.isNotEmpty ? uri.host : 'localhost';
      return 'ws://$host:8081/ws';
    }

    // Production Web (domain like tracking.qutma.com)
    final protocol = uri.scheme == 'https' ? 'wss' : 'ws';
    final portStr = (uri.port != 80 && uri.port != 443 && uri.port != 0)
        ? ':${uri.port}'
        : '';
    return '$protocol://${uri.host}$portStr/ws';
  }

  // Non-web (Mobile / Desktop)
  if (kDebugMode) {
    return 'ws://localhost:8081/ws';
  }

  // Production domain
  return 'wss://tracking.qutma.com/ws';
}

class GPSProvider extends ChangeNotifier {
  final _secureStorage = const FlutterSecureStorage();
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _serverAddress = defaultAddress;
  String _currentRole = 'viewer';
  String _currentUsername = 'Guest';
  String _token = '';

  // Theme Settings
  bool _isDarkTheme = true;
  Color _accentColor = Colors.blueAccent;

  // Administrative users state
  List<Map<String, dynamic>> _users = [];

  // Tracking devices
  final Map<String, Device> _devices = {};
  String? _selectedDeviceId;
  bool _autoFollow = true;
  Timer? _reconnectTimer;

  // Speed Limit & Alerts state
  double _speedLimit = 120.0;
  List<OverspeedAlert> _alerts = [];
  int _unreadAlertsCount = 0;
  final Map<String, DateTime> _lastAlertTime = {};
  final _alertStreamController = StreamController<OverspeedAlert>.broadcast();

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get serverAddress => _serverAddress;
  String get currentRole => _currentRole;
  String get currentUsername => _currentUsername;
  String get token => _token;
  // bool get isDarkTheme => _isDarkTheme;
  Color get accentColor => _accentColor;
  List<Map<String, dynamic>> get users => _users;
  List<Device> get devicesList => _devices.values.toList();
  Map<String, Device> get devicesMap => _devices;
  String? get selectedDeviceId => _selectedDeviceId;
  bool get autoFollow => _autoFollow;
  double get speedLimit => _speedLimit;
  List<OverspeedAlert> get alerts => _alerts;
  int get unreadAlertsCount => _unreadAlertsCount;
  Stream<OverspeedAlert> get alertStream => _alertStreamController.stream;

  Device? get selectedDevice {
    if (_selectedDeviceId != null &&
        _devices.containsKey(_selectedDeviceId) &&
        _devices[_selectedDeviceId]?.enabled == true) {
      return _devices[_selectedDeviceId];
    }
    return null;
  }

  void initializeSession({
    required String role,
    required String username,
    required String serverUrl,
    required String token,
  }) {
    _currentRole = role;
    _currentUsername = username;
    _serverAddress = serverUrl;
    _token = token;
    _saveSession(
      role: role,
      username: username,
      serverUrl: serverUrl,
      token: token,
    );
    connectWebSocket();
  }

  Future<void> _saveSession({
    required String role,
    required String username,
    required String serverUrl,
    required String token,
  }) async {
    await _secureStorage.write(key: 'auth_token', value: token);
    await _secureStorage.write(key: 'auth_role', value: role);
    await _secureStorage.write(key: 'auth_username', value: username);
    await _secureStorage.write(key: 'auth_server', value: serverUrl);
  }

  Future<bool> loadSavedSession() async {
    final token = await _secureStorage.read(key: 'auth_token');
    final role = await _secureStorage.read(key: 'auth_role');
    final username = await _secureStorage.read(key: 'auth_username');
    final serverUrl = await _secureStorage.read(key: 'auth_server');
    final limitStr = await _secureStorage.read(key: 'admin_speed_limit');

    if (limitStr != null) {
      _speedLimit = double.tryParse(limitStr) ?? 120.0;
    }

    if (token != null &&
        token.isNotEmpty &&
        role != null &&
        username != null &&
        serverUrl != null) {
      _currentRole = role;
      _currentUsername = username;
      _serverAddress = defaultAddress;
      _token = token;
      connectWebSocket();
      return true;
    }
    return false;
  }

  Future<void> setSpeedLimit(double limit) async {
    _speedLimit = limit;
    await _secureStorage.write(
      key: 'admin_speed_limit',
      value: limit.toString(),
    );

    // Sync speed limit setting to backend server
    if (_channel != null && _isConnected && _currentRole == 'admin') {
      _channel!.sink.add(
        jsonEncode({
          'type': 'set_speed_limit',
          'limit': limit,
          'token': _token,
        }),
      );
    }

    notifyListeners();
  }

  void _checkOverspeedAlert(Device device) {
    if (_currentRole != 'admin') return;
    if (device.speed > _speedLimit) {
      final now = DateTime.now();
      final lastAlert = _lastAlertTime[device.id];
      if (lastAlert == null || now.difference(lastAlert).inSeconds >= 30) {
        _lastAlertTime[device.id] = now;
        final alert = OverspeedAlert(
          id: '${device.id}_${now.millisecondsSinceEpoch}',
          deviceId: device.id,
          deviceName: device.displayName,
          speed: device.speed,
          limit: _speedLimit,
          timestamp: now,
        );
        _alerts.insert(0, alert);
        _unreadAlertsCount++;
        _alertStreamController.add(alert);
        notifyListeners();
      }
    }
  }

  void markAlertsAsRead() {
    for (var alert in _alerts) {
      alert.isRead = true;
    }
    _unreadAlertsCount = 0;
    notifyListeners();
  }

  void clearAlerts() {
    _alerts.clear();
    _unreadAlertsCount = 0;
    notifyListeners();
  }

  Future<void> clearSession() async {
    await _secureStorage.delete(key: 'auth_token');
    await _secureStorage.delete(key: 'auth_role');
    await _secureStorage.delete(key: 'auth_username');
    await _secureStorage.delete(key: 'auth_server');
    _token = '';
    _isConnected = false;
    _channel?.sink.close();
    notifyListeners();
  }

  void connectWebSocket() {
    if (_isConnecting || _isConnected) return;

    _isConnecting = true;
    notifyListeners();

    try {
      final tokenQuery = _token.isNotEmpty ? '?token=$_token' : '';
      final uri = Uri.parse('$_serverAddress$tokenQuery');
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
          if (item is Map) {
            final mapItem = Map<String, dynamic>.from(item);
            final devId = mapItem['deviceId'].toString();
            final oldHistory = _devices[devId]?.history ?? [];
            _devices[devId] = Device.fromJson(mapItem, oldHistory);
          }
        }
        _setDefaultSelection();
        notifyListeners();
      } else if (type == 'location_update' && data is Map) {
        final mapData = Map<String, dynamic>.from(data);
        final devId = mapData['deviceId'].toString();
        final oldHistory = _devices[devId]?.history ?? [];
        final updatedDevice = Device.fromJson(mapData, oldHistory);
        _devices[devId] = updatedDevice;

        _checkOverspeedAlert(updatedDevice);
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
            enabled: dev.enabled,
            name: parsed['name']?.toString(),
            color: parsed['color']?.toString(),
            carType: parsed['carType']?.toString(),
            additionalData: parsed['additionalData'] != null
                ? Map<String, dynamic>.from(parsed['additionalData'] as Map)
                : null,
          );
          notifyListeners();
        }
      } else if (type == 'users_list_response') {
        if (parsed['success'] == true && parsed['users'] is List) {
          _users = List<Map<String, dynamic>>.from(
            (parsed['users'] as List).map(
              (u) => Map<String, dynamic>.from(u as Map),
            ),
          );
          notifyListeners();
        }
      } else if (type == 'overspeed_notification' && data is Map) {
        final alertMap = Map<String, dynamic>.from(data);
        final alert = OverspeedAlert(
          id:
              alertMap['id']?.toString() ??
              '${alertMap['deviceId']}_${DateTime.now().millisecondsSinceEpoch}',
          deviceId: alertMap['deviceId'].toString(),
          deviceName:
              alertMap['deviceName']?.toString() ??
              'Device ${alertMap['deviceId']}',
          speed: (alertMap['speed'] as num?)?.toDouble() ?? 0.0,
          limit: (alertMap['limit'] as num?)?.toDouble() ?? _speedLimit,
          timestamp: alertMap['timestamp'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  (alertMap['timestamp'] as num).toInt(),
                )
              : DateTime.now(),
        );

        // Deduplicate in case client also generated one recently
        _alerts.removeWhere((a) => a.id == alert.id);
        _alerts.insert(0, alert);
        _unreadAlertsCount++;
        _alertStreamController.add(alert);
        notifyListeners();
      } else if (type == 'speed_limit_updated') {
        if (parsed['limit'] != null) {
          _speedLimit = (parsed['limit'] as num).toDouble();
          notifyListeners();
        }
      } else if (type == 'create_user_response') {
        fetchUsers();
      } else if (type == 'delete_user_response') {
        fetchUsers();
      }
    } catch (e) {
      debugPrint('Error parsing WebSocket provider message: $e');
    }
  }

  // Theme Settings actions
  void toggleTheme(bool isDark) {
    _isDarkTheme = isDark;
    notifyListeners();
  }

  void setAccentColor(Color color) {
    _accentColor = color;
    notifyListeners();
  }

  // User Management actions
  void fetchUsers() {
    if (_channel != null && _isConnected && _currentRole == 'admin') {
      _channel!.sink.add(
        jsonEncode({
          'type': 'get_users',
          'role': _currentRole,
          'token': _token,
        }),
      );
    }
  }

  void createUser(String username, String password, String role) {
    if (_channel != null && _isConnected && _currentRole == 'admin') {
      _channel!.sink.add(
        jsonEncode({
          'type': 'create_user',
          'role': _currentRole,
          'username': username,
          'password': password,
          'userRole': role,
          'token': _token,
        }),
      );
    }
  }

  void deleteUser(dynamic userId) {
    if (_channel != null && _isConnected && _currentRole == 'admin') {
      _channel!.sink.add(
        jsonEncode({
          'type': 'delete_user',
          'role': _currentRole,
          'userId': userId,
          'token': _token,
        }),
      );
    }
  }

  void _setDefaultSelection() {
    final enabledDevices = _devices.values.where((d) => d.enabled);
    if (_selectedDeviceId == null ||
        (_devices[_selectedDeviceId]?.enabled == false)) {
      if (enabledDevices.isNotEmpty) {
        _selectedDeviceId = enabledDevices.first.id;
      } else {
        _selectedDeviceId = null;
      }
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
      _channel!.sink.add(
        jsonEncode({
          'type': 'update_device_metadata',
          'deviceId': deviceId,
          'name': name,
          'color': color,
          'carType': carType,
          'additionalData': additionalData,
          'role': _currentRole,
          'token': _token,
        }),
      );
    }
  }

  void toggleDeviceEnabled(String deviceId, bool enabled) {
    if (_channel != null && _isConnected && _currentRole == 'admin') {
      _channel!.sink.add(
        jsonEncode({
          'type': 'toggle_device_enabled',
          'deviceId': deviceId,
          'enabled': enabled,
          'token': _token,
        }),
      );
    }
  }

  void fetchDevices() {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(
        jsonEncode({'type': 'fetch_devices', 'token': _token}),
      );
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
