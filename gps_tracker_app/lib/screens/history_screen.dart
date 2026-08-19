import 'dart:async';
import 'dart:convert';
import 'dart:ui';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWeb = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      body: Stack(
        children: [
          // Map
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
                      strokeWidth: 4.0,
                      color: theme.colorScheme.primary.withValues(alpha: 0.8),
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    // Start
                    Marker(
                      point: _historyRoutePoints.first,
                      width: 36,
                      height: 36,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Color(0xFF10B981), size: 22),
                      ),
                    ),
                    // End
                    Marker(
                      point: _historyRoutePoints.last,
                      width: 36,
                      height: 36,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.stop_rounded,
                            color: Color(0xFFEF4444), size: 22),
                      ),
                    ),
                    // Current playback
                    if (_historyPlaybackIndex < _historyRoutePoints.length)
                      Marker(
                        point: _historyRoutePoints[_historyPlaybackIndex],
                        width: 70,
                        height: 70,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${_parseNum(_historyPointsData[_historyPlaybackIndex]['speed']).toStringAsFixed(1)} km/h',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.directions_car_rounded,
                              color: theme.colorScheme.primary,
                              size: 26,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),

          // Top header
          Positioned(
            top: isWeb ? 16 : 50,
            left: 16,
            right: 16,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1523).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timeline_rounded,
                              color: theme.colorScheme.primary, size: 18),
                          const SizedBox(width: 10),
                          const Text(
                            'Route History',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1523).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isConnected
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isConnected ? 'Connected' : 'Offline',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: isWeb ? 20 : 100,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1523).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Date + quick filter
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
                                        setState(() =>
                                            _historySelectedDate = picked);
                                        if (_historySelectedDeviceId != null) {
                                          _requestHistory(
                                              _historySelectedDeviceId!,
                                              picked);
                                        }
                                      }
                                    },
                                    icon: Icon(Icons.calendar_today_rounded,
                                        size: 15, color: theme.colorScheme.primary),
                                    label: Text(
                                      "${_historySelectedDate.year}-${_historySelectedDate.month.toString().padLeft(2, '0')}-${_historySelectedDate.day.toString().padLeft(2, '0')}",
                                      style: const TextStyle(
                                          fontSize: 13, color: Colors.white),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                          color:
                                              Colors.white.withValues(alpha: 0.1)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () {
                                    final yesterday = DateTime.now()
                                        .subtract(const Duration(days: 1));
                                    setState(() =>
                                        _historySelectedDate = yesterday);
                                    if (_historySelectedDeviceId != null) {
                                      _requestHistory(
                                          _historySelectedDeviceId!,
                                          yesterday);
                                    }
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.05),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                  child: Text(
                                    'Yesterday',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Device chips
                            Text(
                              'SELECT VEHICLE',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_historyDevices.isEmpty)
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'No devices found',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.3),
                                      fontSize: 12,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.refresh_rounded,
                                        size: 16,
                                        color: theme.colorScheme.primary),
                                    onPressed: _requestDevicesList,
                                  ),
                                ],
                              )
                            else
                              SizedBox(
                                height: 40,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: _historyDevices.map((devId) {
                                    final isSelected =
                                        devId == _historySelectedDeviceId;
                                    return GestureDetector(
                                      onTap: () => _requestHistory(
                                          devId, _historySelectedDate),
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? theme.colorScheme.primary
                                              : Colors.white
                                                  .withValues(alpha: 0.05),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.directions_car_rounded,
                                              size: 14,
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.white.withValues(
                                                      alpha: 0.5),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              devId,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.white.withValues(
                                                        alpha: 0.6),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),

                            // Playback
                            if (_isLoadingHistory)
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: theme.colorScheme.primary,
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                ),
                              )
                            else if (_historyRoutePoints.isNotEmpty) ...[
                              Divider(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  height: 24),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${_historyRoutePoints.length} points',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          Colors.white.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  Text(
                                    '${_historyPlaybackIndex + 1}/${_historyRoutePoints.length}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                min: 0,
                                max: (_historyRoutePoints.length - 1)
                                    .toDouble(),
                                value: _historyPlaybackIndex.toDouble(),
                                onChanged: (val) {
                                  setState(() =>
                                      _historyPlaybackIndex = val.toInt());
                                  _mapController.move(
                                    _getMapCenterWithOffset(
                                        _historyRoutePoints[
                                            _historyPlaybackIndex]),
                                    _mapController.camera.zoom,
                                  );
                                },
                              ),
                              // Telemetry
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        _buildTelemetryTile(
                                          Icons.speed_rounded,
                                          'Speed',
                                          '${_parseNum(_historyPointsData[_historyPlaybackIndex]['speed']).toStringAsFixed(1)} km/h',
                                        ),
                                        _buildTelemetryTile(
                                          Icons.explore_rounded,
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
                                          Icons.cloud_outlined,
                                          'Altitude',
                                          '${_parseNum(_historyPointsData[_historyPlaybackIndex]['altitude']).toStringAsFixed(0)}m',
                                        ),
                                        _buildTelemetryTile(
                                          Icons.schedule_rounded,
                                          'Time',
                                          _historyPointsData[_historyPlaybackIndex]
                                                  ['gps_time']
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
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                child: Center(
                                  child: Text(
                                    'No history data for this date',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.3),
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
        Icon(icon,
            size: 15,
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
            ),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
