import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class HistoryScreen extends StatefulWidget {
  final String serverAddress;
  final String token;

  const HistoryScreen({
    super.key,
    required this.serverAddress,
    required this.token,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final MapController _mapController = MapController();
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isLoadingHistory = false;

  // History State
  List<String> _historyDevices = [];
  String? _historySelectedDeviceId;
  DateTime _historySelectedDate = DateTime.now();
  List<LatLng> _historyRoutePoints = [];
  List<Map<String, dynamic>> _historyPointsData = [];
  int _historyPlaybackIndex = 0;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
  }

  @override
  void dispose() {
    _isConnected = false;
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  void _connectWebSocket() {
    try {
      final uri = Uri.parse(widget.serverAddress);
      _channel = WebSocketChannel.connect(uri);

      _isConnected = true;
      bool _hasRequestedDevices = false;

      _subscription = _channel!.stream.listen(
        (message) {
          if (mounted) {
            if (!_hasRequestedDevices) {
              _hasRequestedDevices = true;
              _requestDevicesList();
            }
            _handleIncomingMessage(message);
          }
        },
        onError: (err) {
          debugPrint('History WS Error: $err');
          if (mounted) {
            setState(() {
              _isConnected = false;
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _isConnected = false;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('History WS Connect Exception: $e');
    }
  }

  void _requestDevicesList() {
    if (mounted && _channel != null && _isConnected) {
      _channel!.sink.add(
        jsonEncode({'type': 'get_devices', 'token': widget.token}),
      );
    }
  }

  void _requestHistory(String deviceId, DateTime date) {
    debugPrint('[HistoryScreen] _requestHistory called: deviceId=$deviceId, date=$date, connected=$_isConnected, channel=${_channel != null}');
    if (mounted && _channel != null && _isConnected) {
      setState(() {
        _isLoadingHistory = true;
        _historySelectedDeviceId = deviceId;
        _historyRoutePoints = [];
        _historyPointsData = [];
        _historyPlaybackIndex = 0;
      });
      final formattedDate =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final payload = jsonEncode({
        'type': 'get_history',
        'deviceId': deviceId,
        'date': formattedDate,
        'token': widget.token,
      });
      debugPrint('[HistoryScreen] Sending: $payload');
      _channel!.sink.add(payload);
    } else {
      debugPrint('[HistoryScreen] _requestHistory SKIPPED: mounted=$mounted, channel=${_channel != null}, connected=$_isConnected');
    }
  }

  double _parseNum(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  LatLng _getMapCenterWithOffset(LatLng point) {
    if (!mounted) return point;
    final isMobile = MediaQuery.of(context).size.width < 800;
    if (isMobile) {
      // Shift map center south so the vehicle marker moves up, keeping it out of the bottom card
      return LatLng(point.latitude - 0.008, point.longitude);
    }
    return point;
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      final parsed = jsonDecode(message) as Map<String, dynamic>;
      final type = parsed['type'];
      debugPrint('[HistoryScreen] Received message type: $type');

      if (type == 'devices_list_response') {
        final list = parsed['devices'] as List;
        setState(() {
          _historyDevices = list.map((e) => e.toString()).toList();
        });
      } else if (type == 'history_response') {
        try {
          final list = parsed['history'] as List;
          debugPrint('[HistoryScreen] History points count: ${list.length}');
          final pointsData = list
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final routePoints = list.map((item) {
            final mapItem = Map<String, dynamic>.from(item as Map);
            final lat = _parseNum(mapItem['latitude']);
            final lng = _parseNum(mapItem['longitude']);
            return LatLng(lat, lng);
          }).toList();

          setState(() {
            _isLoadingHistory = false;
            _historyPointsData = pointsData;
            _historyRoutePoints = routePoints;
            _historyPlaybackIndex = 0;
          });

          if (routePoints.isNotEmpty) {
            _mapController.move(_getMapCenterWithOffset(routePoints.first), 13.0);
          }
        } catch (e) {
          debugPrint('[HistoryScreen] Error parsing history data: $e');
          setState(() {
            _isLoadingHistory = false;
          });
        }
      } else if (type == 'unauthorized_response') {
        debugPrint('[HistoryScreen] Unauthorized! ${parsed['message']}');
        setState(() {
          _isLoadingHistory = false;
        });
      } else {
        // Other message types (devices_state, location_update, etc.) — ignore silently
        if (_isLoadingHistory && type != 'devices_state' && type != 'location_update') {
          debugPrint('[HistoryScreen] Unexpected type while loading: $type — full: $parsed');
        }
      }
    } catch (e) {
      debugPrint('[HistoryScreen] Error parsing message: $e');
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  Widget _buildTelemetryTile(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.cyanAccent),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Route History Lookup'),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? Colors.greenAccent : Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _isConnected ? 'Connected' : 'Offline',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map Layer
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(24.573213, 46.546881),
              initialZoom: 12.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              if (_historyRoutePoints.isNotEmpty) ...[
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _historyRoutePoints,
                      strokeWidth: 5.0,
                      color: Colors.cyanAccent.withValues(alpha: 0.9),
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    // Start marker (Green)
                    Marker(
                      point: _historyRoutePoints.first,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.play_circle_fill,
                        color: Colors.greenAccent,
                        size: 30,
                      ),
                    ),
                    // End marker (Red)
                    Marker(
                      point: _historyRoutePoints.last,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.stop_circle,
                        color: Colors.redAccent,
                        size: 30,
                      ),
                    ),
                    // Playback vehicle marker
                    if (_historyPlaybackIndex < _historyRoutePoints.length)
                      Marker(
                        point: _historyRoutePoints[_historyPlaybackIndex],
                        width: 70,
                        height: 70,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${_parseNum(_historyPointsData[_historyPlaybackIndex]['speed']).toStringAsFixed(1)} km/h',
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.directions_car,
                              color: Colors.yellowAccent,
                              size: 28,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),

          // Bottom Filter Panel & Playback Controller (Centered and max 600px width for desktop)
          Positioned(
            bottom: MediaQuery.of(context).size.width >= 800 ? 24 : 105,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.cyan.withValues(alpha: 0.3),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 15,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Filter inputs (Date Picker and Fast Filter Buttons)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _historySelectedDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _historySelectedDate = picked;
                                    });
                                    if (_historySelectedDeviceId != null) {
                                      _requestHistory(
                                        _historySelectedDeviceId!,
                                        picked,
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                  color: Colors.cyan,
                                ),
                                label: Text(
                                  "${_historySelectedDate.year}-${_historySelectedDate.month.toString().padLeft(2, '0')}-${_historySelectedDate.day.toString().padLeft(2, '0')}",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white24),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                final yesterday = DateTime.now().subtract(
                                  const Duration(days: 1),
                                );
                                setState(() {
                                  _historySelectedDate = yesterday;
                                });
                                if (_historySelectedDeviceId != null) {
                                  _requestHistory(
                                    _historySelectedDeviceId!,
                                    yesterday,
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.cyan.shade900,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text(
                                'Yesterday',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.cyanAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // List of devices
                        const Text(
                          'Select Car / Device ID:',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                        const SizedBox(height: 6),
                        if (_historyDevices.isEmpty)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'No devices found in database.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.refresh,
                                  size: 16,
                                  color: Colors.cyan,
                                ),
                                onPressed: _requestDevicesList,
                              ),
                            ],
                          )
                        else
                          SizedBox(
                            height: 42,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: _historyDevices.map((devId) {
                                final isSelected =
                                    devId == _historySelectedDeviceId;
                                return GestureDetector(
                                  onTap: () {
                                    _requestHistory(
                                      devId,
                                      _historySelectedDate,
                                    );
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.cyan
                                          : const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.cyanAccent
                                            : Colors.white10,
                                        width: 1,
                                      ),
                                    ),
                                    child: Center(
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.directions_car,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            devId,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                        // Route details and playback controls
                        if (_isLoadingHistory)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(
                                color: Colors.cyan,
                              ),
                            ),
                          )
                        else if (_historyRoutePoints.isNotEmpty) ...[
                          const Divider(color: Colors.white10, height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Route points: ${_historyRoutePoints.length}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                'Point: ${_historyPlaybackIndex + 1}/${_historyRoutePoints.length}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.cyanAccent,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            min: 0,
                            max: (_historyRoutePoints.length - 1).toDouble(),
                            value: _historyPlaybackIndex.toDouble(),
                            activeColor: Colors.cyanAccent,
                            inactiveColor: Colors.white24,
                            onChanged: (val) {
                              setState(() {
                                _historyPlaybackIndex = val.toInt();
                              });
                              _mapController.move(
                                _getMapCenterWithOffset(
                                  _historyRoutePoints[_historyPlaybackIndex],
                                ),
                                _mapController.camera.zoom,
                              );
                            },
                          ),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildTelemetryTile(
                                      Icons.speed,
                                      'Speed',
                                      '${_parseNum(_historyPointsData[_historyPlaybackIndex]['speed']).toStringAsFixed(1)} km/h',
                                    ),
                                    _buildTelemetryTile(
                                      Icons.explore,
                                      'Bearing',
                                      '${_parseNum(_historyPointsData[_historyPlaybackIndex]['direction']).toStringAsFixed(0)}°',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildTelemetryTile(
                                      Icons.cloud,
                                      'Altitude',
                                      '${_parseNum(_historyPointsData[_historyPlaybackIndex]['altitude']).toStringAsFixed(0)}m',
                                    ),
                                    _buildTelemetryTile(
                                      Icons.timer,
                                      'GPS Time',
                                      _historyPointsData[_historyPlaybackIndex]['gps_time']
                                          .toString()
                                          .replaceAll('T', ' ')
                                          .replaceAll('Z', '')
                                          .split('.')
                                          .first,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ] else if (_historySelectedDeviceId != null) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Center(
                              child: Text(
                                'No history coordinates recorded for this date.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
