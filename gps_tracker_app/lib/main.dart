import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(const GPSApp());
}

class GPSApp extends StatelessWidget {
  const GPSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Active GPS Fleet Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6), // Indigo/Blue
          secondary: Color(0xFF10B981), // Emerald/Green
          surface: Color(0xFF1E293B), // Slate 800
          background: Color(0xFF0F172A),
          error: Color(0xFFEF4444),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E293B),
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const GPSDashboard(),
    );
  }
}

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
  });

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
    );
  }
}

class GPSDashboard extends StatefulWidget {
  const GPSDashboard({super.key});

  @override
  State<GPSDashboard> createState() => _GPSDashboardState();
}

class _GPSDashboardState extends State<GPSDashboard> {
  final MapController _mapController = MapController();
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _serverAddress = 'ws://37.104.207.61:3000'; // Default IP/port
  
  // Track active devices
  final Map<String, Device> _devices = {};
  String? _selectedDeviceId;
  bool _autoFollow = true;
  Timer? _reconnectTimer;

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  void _connectWebSocket() {
    if (_isConnecting || _isConnected) return;

    setState(() {
      _isConnecting = true;
    });

    _reconnectTimer?.cancel();
    
    try {
      final uri = Uri.parse(_serverAddress);
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (message) {
          _isConnecting = false;
          if (!_isConnected) {
            setState(() {
              _isConnected = true;
            });
          }
          _handleIncomingMessage(message);
        },
        onError: (error) {
          debugPrint('WS Connection Error: $error');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('WS Connection Closed');
          _handleDisconnect();
        },
      );
    } catch (e) {
      debugPrint('WS Initial Connection Exception: $e');
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    setState(() {
      _isConnected = false;
      _isConnecting = false;
    });
    
    // Auto-reconnect every 5 seconds
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (!_isConnected && !_isConnecting) {
        _connectWebSocket();
      }
    });
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      final parsed = jsonDecode(message) as Map<String, dynamic>;
      final type = parsed['type'];
      final data = parsed['data'];

      setState(() {
        if (type == 'devices_state' && data is List) {
          for (final item in data) {
            final devId = item['deviceId'].toString();
            final oldHistory = _devices[devId]?.history ?? [];
            _devices[devId] = Device.fromJson(item, oldHistory);
          }
        } else if (type == 'location_update' && data is Map) {
          final devId = data['deviceId'].toString();
          final oldHistory = _devices[devId]?.history ?? [];
          final updatedDevice = Device.fromJson(data as Map<String, dynamic>, oldHistory);
          _devices[devId] = updatedDevice;

          // Focus on the selected device if follow is enabled
          if (_selectedDeviceId == devId && _autoFollow) {
            _mapController.move(
              LatLng(updatedDevice.latitude, updatedDevice.longitude),
              _mapController.camera.zoom,
            );
          }
        }

        // If no device is currently selected, pick the first active one
        if (_selectedDeviceId == null && _devices.isNotEmpty) {
          _selectedDeviceId = _devices.keys.first;
          _focusDevice(_devices[_selectedDeviceId!]!);
        }
      });
    } catch (e) {
      debugPrint('Error parsing WebSocket message: $e');
    }
  }

  void _focusDevice(Device device) {
    setState(() {
      _selectedDeviceId = device.id;
    });
    _mapController.move(LatLng(device.latitude, device.longitude), 15.0);
  }

  void _showServerConfigDialog() {
    final controller = TextEditingController(text: _serverAddress);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Server Configuration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter WebSocket server URL to stream coordinates in real-time.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'WebSocket URL',
                  hintText: 'ws://your-ip:8082',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _serverAddress = controller.text.trim();
                });
                _channel?.sink.close();
                _handleDisconnect();
                Navigator.pop(context);
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDevice = _selectedDeviceId != null ? _devices[_selectedDeviceId] : null;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Map Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: selectedDevice != null
                  ? LatLng(selectedDevice.latitude, selectedDevice.longitude)
                  : const LatLng(24.573213, 46.546881), // Default Riyadh Coordinates from logs
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              // Historical Track lines for selected device
              if (selectedDevice != null && selectedDevice.history.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: selectedDevice.history,
                      strokeWidth: 4.0,
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                    ),
                  ],
                ),
              // Markers for all connected devices
              MarkerLayer(
                markers: _devices.values.map((device) {
                  final isSelected = device.id == _selectedDeviceId;
                  final angle = (device.direction * math.pi) / 180.0;

                  return Marker(
                    point: LatLng(device.latitude, device.longitude),
                    width: 90,
                    height: 90,
                    child: GestureDetector(
                      onTap: () => _focusDevice(device),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Small speed / label badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.blue : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white24, width: 1),
                              boxShadow: const [
                                BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))
                              ]
                            ),
                            child: Text(
                              '${device.speed.toStringAsFixed(1)} km/h',
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Custom Arrow representing rotation
                          Transform.rotate(
                            angle: angle,
                            child: Icon(
                              Icons.navigation,
                              size: isSelected ? 34 : 26,
                              color: isSelected
                                  ? const Color(0xFF3B82F6) // Active blue
                                  : const Color(0xFF10B981), // Green
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Pulse dot
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: isSelected ? Colors.blue : Colors.orangeAccent,
                                  blurRadius: 6,
                                  spreadRadius: 2,
                                )
                              ]
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // 2. Premium Top Bar Overlay
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // Server Config & Connection state
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))
                      ],
                    ),
                    child: Row(
                      children: [
                        // Status Indicator
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isConnected
                                ? Colors.amber
                                : _isConnecting
                                    ? Colors.amber
                                    : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isConnected
                                    ? 'Connected Live'
                                    : _isConnecting
                                        ? 'Reconnecting...'
                                        : 'Disconnected',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                _serverAddress,
                                style: const TextStyle(color: Colors.grey, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings, color: Colors.blue),
                          onPressed: _showServerConfigDialog,
                          tooltip: 'Server Settings',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Auto follow button
                FloatingActionButton.small(
                  backgroundColor: _autoFollow ? Colors.blue : const Color(0xFF0F172A),
                  onPressed: () {
                    setState(() {
                      _autoFollow = !_autoFollow;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_autoFollow ? 'Auto-follow Device Enabled' : 'Auto-follow Device Disabled'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  child: Icon(
                    _autoFollow ? Icons.gps_fixed : Icons.gps_not_fixed,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // 3. Right Sidebar / Bottom Sheet for Active Devices
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quick horizontal device selector list
                if (_devices.isNotEmpty)
                  SizedBox(
                    height: 55,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _devices.values.map((device) {
                        final isSelected = device.id == _selectedDeviceId;
                        final isRecentlyUpdated = DateTime.now().difference(device.lastUpdated).inSeconds < 30;

                        return GestureDetector(
                          onTap: () => _focusDevice(device),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF1D4ED8)
                                  : const Color(0xFF1E293B).withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? Colors.blue : Colors.white10,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.directions_car,
                                  color: isRecentlyUpdated ? Colors.orangeAccent : Colors.grey,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'ID: ${device.id}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                    Text(
                                      '${device.speed.toStringAsFixed(1)} km/h',
                                      style: const TextStyle(color: Colors.grey, fontSize: 9),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 12),
                
                // Detailed telemetry panel card for selected device
                if (selectedDevice != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 15, offset: Offset(0, 5))
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.sensors, color: Colors.orangeAccent, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'TELEMETRY: ${selectedDevice.id}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    letterSpacing: 0.5,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Updated ${DateTime.now().difference(selectedDevice.lastUpdated).inSeconds}s ago',
                              style: const TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white10, height: 20),
                        
                        // 2x2 Telemetry Info
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          childAspectRatio: 3.5,
                          children: [
                            _buildTelemetryTile(
                              Icons.speed,
                              'Speed',
                              '${selectedDevice.speed.toStringAsFixed(1)} km/h',
                            ),
                            _buildTelemetryTile(
                              Icons.explore,
                              'Bearing',
                              '${selectedDevice.direction.toStringAsFixed(0)}°',
                            ),
                            _buildTelemetryTile(
                              Icons.cloud,
                              'Altitude',
                              '${selectedDevice.altitude.toStringAsFixed(0)}m',
                            ),
                            _buildTelemetryTile(
                              Icons.timer,
                              'Time',
                              selectedDevice.gpsTime.split(' ').last,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        // Lat/Long indicator
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Text(
                                'Lat: ${selectedDevice.latitude.toStringAsFixed(6)}',
                                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                              ),
                              Text(
                                'Lon: ${selectedDevice.longitude.toStringAsFixed(6)}',
                                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Text(
                        'Waiting for active devices to connect...',
                        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryTile(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.blueAccent),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ],
    );
  }
}
