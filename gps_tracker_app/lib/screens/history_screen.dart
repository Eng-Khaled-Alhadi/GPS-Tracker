import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum HistoryDateFilter { today, yesterday, custom }

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
  HistoryDateFilter _dateFilter = HistoryDateFilter.today;
  List<LatLng> _historyRoutePoints = [];
  List<Map<String, dynamic>> _historyPointsData = [];
  int _historyPlaybackIndex = 0;
  StreamSubscription? _subscription;

  // Auto-playback
  bool _isPlaying = false;
  Timer? _playbackTimer;
  int _playbackSpeed = 1; // 1x, 2x, 4x

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
  }

  @override
  void dispose() {
    _isPlaying = false;
    _playbackTimer?.cancel();
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
      bool hasRequestedDevices = false;

      _subscription = _channel!.stream.listen(
        (message) {
          if (mounted) {
            if (!hasRequestedDevices) {
              hasRequestedDevices = true;
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
    _stopPlayback();
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
      _channel!.sink.add(payload);
    }
  }

  void _selectDateFilter(HistoryDateFilter filter) async {
    final now = DateTime.now();
    DateTime newDate;

    if (filter == HistoryDateFilter.today) {
      newDate = now;
      setState(() {
        _dateFilter = HistoryDateFilter.today;
        _historySelectedDate = newDate;
      });
    } else if (filter == HistoryDateFilter.yesterday) {
      newDate = now.subtract(const Duration(days: 1));
      setState(() {
        _dateFilter = HistoryDateFilter.yesterday;
        _historySelectedDate = newDate;
      });
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: _historySelectedDate,
        firstDate: DateTime(2020),
        lastDate: now,
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                    surface: const Color(0xFF141B2D),
                  ),
            ),
            child: child!,
          );
        },
      );
      if (picked != null) {
        newDate = picked;
        // Check if picked is today or yesterday
        if (picked.year == now.year &&
            picked.month == now.month &&
            picked.day == now.day) {
          setState(() {
            _dateFilter = HistoryDateFilter.today;
            _historySelectedDate = newDate;
          });
        } else if (picked.year == now.year &&
            picked.month == now.month &&
            picked.day == now.day - 1) {
          setState(() {
            _dateFilter = HistoryDateFilter.yesterday;
            _historySelectedDate = newDate;
          });
        } else {
          setState(() {
            _dateFilter = HistoryDateFilter.custom;
            _historySelectedDate = newDate;
          });
        }
      } else {
        return;
      }
    }

    if (_historySelectedDeviceId != null) {
      _requestHistory(_historySelectedDeviceId!, _historySelectedDate);
    }
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _stopPlayback();
    } else {
      _startPlayback();
    }
  }

  void _startPlayback() {
    if (_historyRoutePoints.isEmpty) return;
    setState(() => _isPlaying = true);
    _playbackTimer?.cancel();

    final intervalMs = (500 / _playbackSpeed).round();
    _playbackTimer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_historyPlaybackIndex < _historyRoutePoints.length - 1) {
        setState(() {
          _historyPlaybackIndex++;
        });
        _mapController.move(
          _getMapCenterWithOffset(_historyRoutePoints[_historyPlaybackIndex]),
          _mapController.camera.zoom,
        );
      } else {
        _stopPlayback();
      }
    });
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    if (mounted) {
      setState(() => _isPlaying = false);
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
      return LatLng(point.latitude - 0.006, point.longitude);
    }
    return point;
  }

  void _handleIncomingMessage(dynamic message) {
    try {
      final parsed = jsonDecode(message) as Map<String, dynamic>;
      final type = parsed['type'];

      if (type == 'devices_list_response') {
        final list = parsed['devices'] as List;
        setState(() {
          _historyDevices = list.map((e) => e.toString()).toList();
          if (_historySelectedDeviceId == null && _historyDevices.isNotEmpty) {
            _historySelectedDeviceId = _historyDevices.first;
            _requestHistory(_historyDevices.first, _historySelectedDate);
          }
        });
      } else if (type == 'history_response') {
        try {
          final list = parsed['history'] as List;
          final pointsData =
              list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
            _mapController.move(
              _getMapCenterWithOffset(routePoints.first),
              13.5,
            );
          }
        } catch (e) {
          debugPrint('Error parsing history data: $e');
          setState(() => _isLoadingHistory = false);
        }
      } else if (type == 'unauthorized_response') {
        setState(() => _isLoadingHistory = false);
      }
    } catch (e) {
      debugPrint('Error parsing message: $e');
      setState(() => _isLoadingHistory = false);
    }
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return "${months[d.month - 1]} ${d.day}, ${d.year}";
  }

  double _calculateMaxSpeed() {
    double maxSpeed = 0.0;
    for (var point in _historyPointsData) {
      final speed = _parseNum(point['speed']);
      if (speed > maxSpeed) maxSpeed = speed;
    }
    return maxSpeed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWeb = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
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
                      strokeWidth: 4.0,
                      color: theme.colorScheme.primary.withValues(alpha: 0.85),
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    // Start Marker
                    Marker(
                      point: _historyRoutePoints.first,
                      width: 38,
                      height: 38,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    // End Marker
                    Marker(
                      point: _historyRoutePoints.last,
                      width: 38,
                      height: 38,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.stop_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    // Current Playback Position
                    if (_historyPlaybackIndex < _historyRoutePoints.length)
                      Marker(
                        point: _historyRoutePoints[_historyPlaybackIndex],
                        width: 70,
                        height: 70,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: theme.colorScheme.primary,
                                  width: 1,
                                ),
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
                            const SizedBox(height: 2),
                            Icon(
                              Icons.directions_car_rounded,
                              color: theme.colorScheme.primary,
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

          // Top Header: Date Filter Bar
          Positioned(
            top: isWeb ? 16 : 50,
            left: 16,
            right: 16,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1523).withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // Filter Pill 1: Today
                          _buildDateFilterChip(
                            label: 'Today',
                            isSelected: _dateFilter == HistoryDateFilter.today,
                            onTap: () => _selectDateFilter(HistoryDateFilter.today),
                            theme: theme,
                          ),
                          const SizedBox(width: 6),

                          // Filter Pill 2: Yesterday
                          _buildDateFilterChip(
                            label: 'Yesterday',
                            isSelected: _dateFilter == HistoryDateFilter.yesterday,
                            onTap: () =>
                                _selectDateFilter(HistoryDateFilter.yesterday),
                            theme: theme,
                          ),
                          const SizedBox(width: 6),

                          // Filter Pill 3: Custom Date Picker
                          Expanded(
                            child: InkWell(
                              onTap: () =>
                                  _selectDateFilter(HistoryDateFilter.custom),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: _dateFilter == HistoryDateFilter.custom
                                      ? theme.colorScheme.primary
                                          .withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _dateFilter == HistoryDateFilter.custom
                                        ? theme.colorScheme.primary
                                        : Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.calendar_month_rounded,
                                      size: 15,
                                      color: _dateFilter ==
                                              HistoryDateFilter.custom
                                          ? theme.colorScheme.primary
                                          : Colors.white70,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _dateFilter == HistoryDateFilter.custom
                                            ? _formatDate(_historySelectedDate)
                                            : 'Select Date',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: _dateFilter ==
                                                  HistoryDateFilter.custom
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: _dateFilter ==
                                                  HistoryDateFilter.custom
                                              ? Colors.white
                                              : Colors.white70,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_drop_down_rounded,
                                      size: 18,
                                      color: Colors.white.withValues(alpha: 0.4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom Controls: Vehicle Selector & Playback
          Positioned(
            bottom: isWeb ? 20 : 100,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1523).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Row 1: Vehicle Chips
                            Row(
                              children: [
                                Text(
                                  'VEHICLE',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const Spacer(),
                                if (_historyRoutePoints.isNotEmpty)
                                  Text(
                                    '${_historyRoutePoints.length} points • Max ${_calculateMaxSpeed().toStringAsFixed(0)} km/h',
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            if (_historyDevices.isEmpty)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Searching for vehicles...',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.4),
                                      fontSize: 12,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                      color: theme.colorScheme.primary,
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
                                      onTap: () => _requestHistory(
                                        devId,
                                        _historySelectedDate,
                                      ),
                                      child: Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? theme.colorScheme.primary
                                              : Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: isSelected
                                                ? theme.colorScheme.primary
                                                : Colors.white
                                                    .withValues(alpha: 0.06),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.directions_car_rounded,
                                              size: 15,
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.white.withValues(alpha: 0.6),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              devId,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                                color: isSelected
                                                    ? Colors.white
                                                    : Colors.white.withValues(alpha: 0.8),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),

                            // State 1: Loading
                            if (_isLoadingHistory)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          color: theme.colorScheme.primary,
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Loading trip coordinates for ${_formatDate(_historySelectedDate)}...',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.6),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            // State 2: Route Loaded & Playback Controls
                            else if (_historyRoutePoints.isNotEmpty) ...[
                              Divider(
                                color: Colors.white.withValues(alpha: 0.06),
                                height: 20,
                              ),
                              // Playback Action Bar
                              Row(
                                children: [
                                  // Play / Pause Button
                                  ElevatedButton.icon(
                                    onPressed: _togglePlayback,
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      backgroundColor: _isPlaying
                                          ? const Color(0xFFEF4444)
                                          : theme.colorScheme.primary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    icon: Icon(
                                      _isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 18,
                                    ),
                                    label: Text(
                                      _isPlaying ? 'Pause' : 'Play Route',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Speed multiplier (1x / 2x / 4x)
                                  if (_isPlaying)
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _playbackSpeed =
                                              _playbackSpeed == 1 ? 2 : (_playbackSpeed == 2 ? 4 : 1);
                                        });
                                        _startPlayback();
                                      },
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${_playbackSpeed}x',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),

                                  const Spacer(),
                                  Text(
                                    '${_historyPlaybackIndex + 1} / ${_historyRoutePoints.length}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),

                              // Playback Scrubber Slider
                              SliderTheme(
                                data: theme.sliderTheme.copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7,
                                  ),
                                ),
                                child: Slider(
                                  min: 0,
                                  max: (_historyRoutePoints.length - 1).toDouble(),
                                  value: _historyPlaybackIndex.toDouble(),
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
                              ),

                              // Telemetry Box
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A0E1A),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildTelemetryItem(
                                      Icons.speed_rounded,
                                      'Speed',
                                      '${_parseNum(_historyPointsData[_historyPlaybackIndex]['speed']).toStringAsFixed(1)} km/h',
                                      theme,
                                    ),
                                    _buildTelemetryItem(
                                      Icons.explore_rounded,
                                      'Bearing',
                                      '${_parseNum(_historyPointsData[_historyPlaybackIndex]['direction']).toStringAsFixed(0)}°',
                                      theme,
                                    ),
                                    _buildTelemetryItem(
                                      Icons.schedule_rounded,
                                      'Time',
                                      _historyPointsData[_historyPlaybackIndex]['gps_time']
                                          .toString()
                                          .replaceAll('T', ' ')
                                          .replaceAll('Z', '')
                                          .split('.')
                                          .first
                                          .split(' ')
                                          .last,
                                      theme,
                                    ),
                                  ],
                                ),
                              ),
                            ]
                            // State 3: Empty State for Selected Date
                            else if (_historySelectedDeviceId != null) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.route_outlined,
                                      size: 32,
                                      color: Colors.white.withValues(alpha: 0.25),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No trips recorded for ${_formatDate(_historySelectedDate)}',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Try selecting Yesterday or another date from the calendar.',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.35),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
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

  Widget _buildDateFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildTelemetryItem(
    IconData icon,
    String label,
    String value,
    ThemeData theme,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: theme.colorScheme.primary.withValues(alpha: 0.8),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 9,
              ),
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
