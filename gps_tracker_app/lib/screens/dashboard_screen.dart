import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../providers/gps_provider.dart';

class GPSDashboard extends StatefulWidget {
  const GPSDashboard({super.key});

  @override
  State<GPSDashboard> createState() => _GPSDashboardState();
}

class _GPSDashboardState extends State<GPSDashboard> {
  final MapController _mapController = MapController();
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  void _focusDevice(GPSProvider provider, Device device) {
    if (provider.selectedDeviceId == device.id) {
      provider.selectDevice('');
    } else {
      provider.selectDevice(device.id);
      _mapController.move(LatLng(device.latitude, device.longitude), 15.0);
    }
  }

  void _showEditMetadataDialog(Device device) {
    final gpsProvider = Provider.of<GPSProvider>(context, listen: false);
    if (gpsProvider.currentRole == 'viewer') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permission Denied: Viewer role cannot edit.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final nameController = TextEditingController(text: device.name ?? '');
    final colorController = TextEditingController(text: device.color ?? '');
    final typeController = TextEditingController(text: device.carType ?? '');

    final List<MapEntry<TextEditingController, TextEditingController>>
        customFields = [];
    if (device.additionalData != null) {
      device.additionalData!.forEach((key, value) {
        customFields.add(MapEntry(
          TextEditingController(text: key),
          TextEditingController(text: value.toString()),
        ));
      });
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit: ${device.displayName}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                        hintText: 'e.g. CEO Sedan',
                        prefixIcon: Icon(Icons.label_outline, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: colorController,
                      decoration: const InputDecoration(
                        labelText: 'Color (Hex or name)',
                        hintText: 'e.g. #FF0000 or red',
                        prefixIcon: Icon(Icons.palette_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: typeController,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Type',
                        hintText: 'e.g. Sedan, SUV, Van',
                        prefixIcon: Icon(Icons.local_shipping_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Custom Attributes',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              customFields.add(MapEntry(
                                TextEditingController(),
                                TextEditingController(),
                              ));
                            });
                          },
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Add', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    ...customFields.map((field) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: field.key,
                                decoration: const InputDecoration(
                                    hintText: 'Key', isDense: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: field.value,
                                decoration: const InputDecoration(
                                    hintText: 'Value', isDense: true),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: Colors.redAccent, size: 18),
                              onPressed: () =>
                                  setDialogState(() => customFields.remove(field)),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final Map<String, dynamic> extraData = {};
                    for (final field in customFields) {
                      final k = field.key.text.trim();
                      final v = field.value.text.trim();
                      if (k.isNotEmpty) extraData[k] = v;
                    }
                    gpsProvider.updateDeviceMetadata(
                      deviceId: device.id,
                      name: nameController.text.trim(),
                      color: colorController.text.trim(),
                      carType: typeController.text.trim(),
                      additionalData: extraData,
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GPSProvider>(context);
    final devices = provider.devicesList.where((d) => d.enabled).toList();
    final selectedDevice = provider.selectedDevice;
    final theme = Theme.of(context);
    final isWeb = MediaQuery.of(context).size.width >= 800;

    // Auto-follow
    if (selectedDevice != null && provider.autoFollow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(
          LatLng(selectedDevice.latitude, selectedDevice.longitude),
          _mapController.camera.zoom,
        );
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          // === Map Layer ===
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: selectedDevice != null
                  ? LatLng(selectedDevice.latitude, selectedDevice.longitude)
                  : const LatLng(24.573213, 46.546881),
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
              ),
              if (selectedDevice != null && selectedDevice.history.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: selectedDevice.history,
                      strokeWidth: 3.5,
                      color: theme.colorScheme.primary.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: devices.map((device) {
                  final isSelected = device.id ==
                      (selectedDevice?.id ?? provider.selectedDeviceId);
                  final angle = (device.direction * math.pi) / 180.0;

                  Color arrowColor = isSelected
                      ? theme.colorScheme.primary
                      : const Color(0xFF10B981);
                  if (device.color != null && device.color!.isNotEmpty) {
                    arrowColor = _parseColor(device.color!) ?? arrowColor;
                  }

                  return Marker(
                    point: LatLng(device.latitude, device.longitude),
                    width: 100,
                    height: 100,
                    child: GestureDetector(
                      onTap: () => _focusDevice(provider, device),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (device.name != null && device.name!.trim().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(bottom: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                device.name!,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: arrowColor,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : const Color(0xFF141B2D),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: Text(
                              '${device.speed.toStringAsFixed(1)} km/h',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Transform.rotate(
                            angle: angle,
                            child: Icon(
                              Icons.navigation_rounded,
                              size: isSelected ? 30 : 22,
                              color: arrowColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: arrowColor.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                  spreadRadius: 2,
                                ),
                              ],
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

          // === Top Status Pill ===
          Positioned(
            top: isWeb ? 16 : 50,
            left: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1523).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: provider.isConnected
                              ? const Color(0xFF10B981)
                              : provider.isConnecting
                                  ? Colors.amber
                                  : const Color(0xFFEF4444),
                          boxShadow: [
                            BoxShadow(
                              color: (provider.isConnected
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFFEF4444))
                                  .withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        provider.isConnected
                            ? 'Live'
                            : provider.isConnecting
                                ? 'Connecting'
                                : 'Offline',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${devices.length} active)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // === Auto-follow toggle ===
          Positioned(
            top: isWeb ? 16 : 50,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Material(
                  color: provider.autoFollow
                      ? theme.colorScheme.primary
                      : const Color(0xFF0F1523).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () {
                      provider.setAutoFollow(!provider.autoFollow);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            provider.autoFollow
                                ? 'Auto-follow enabled'
                                : 'Auto-follow disabled',
                          ),
                          duration: const Duration(milliseconds: 900),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            provider.autoFollow
                                ? Icons.gps_fixed_rounded
                                : Icons.gps_not_fixed_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Follow',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(
                                alpha: provider.autoFollow ? 1.0 : 0.6,
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

          // === Bottom Panel ===
          Positioned(
            bottom: isWeb ? 20 : 100,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Device selector horizontal list
                      if (devices.isNotEmpty)
                        SizedBox(
                          height: 46,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: devices.map((device) {
                              final isSelected = device.id ==
                                  (selectedDevice?.id ??
                                      provider.selectedDeviceId);
                              final isRecentlyUpdated = DateTime.now()
                                      .difference(device.lastUpdated)
                                      .inSeconds <
                                  30;

                              return GestureDetector(
                                onTap: () => _focusDevice(provider, device),
                                onLongPress: () =>
                                    _showEditMetadataDialog(device),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : const Color(0xFF141B2D)
                                            .withValues(alpha: 0.92),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : Colors.white
                                              .withValues(alpha: 0.08),
                                    ),
                                    boxShadow: [
                                      if (isSelected)
                                        BoxShadow(
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: 0.35),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isRecentlyUpdated
                                              ? const Color(0xFF10B981)
                                              : Colors.white
                                                  .withValues(alpha: 0.3),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            device.displayName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              color: isSelected
                                                  ? Colors.white
                                                  : Colors.white
                                                      .withValues(alpha: 0.9),
                                            ),
                                          ),
                                          Text(
                                            '${device.speed.toStringAsFixed(1)} km/h',
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Colors.white
                                                      .withValues(alpha: 0.8)
                                                  : Colors.white
                                                      .withValues(alpha: 0.4),
                                              fontSize: 10,
                                            ),
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
                      const SizedBox(height: 10),

                      // Telemetry card
                      if (selectedDevice != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141B2D)
                                    .withValues(alpha: 0.94),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.08)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(Icons.directions_car_rounded,
                                            color: theme.colorScheme.primary,
                                            size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              selectedDevice.displayName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                                color: Colors.white,
                                              ),
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              'ID: ${selectedDevice.id}${selectedDevice.carType != null && selectedDevice.carType!.trim().isNotEmpty ? ' • ${selectedDevice.carType}' : ''}',
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.4),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        _formatElapsedTime(
                                            selectedDevice.lastUpdated),
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.35),
                                          fontSize: 11,
                                        ),
                                      ),
                                      if (provider.currentRole != 'viewer')
                                        IconButton(
                                          icon: Icon(Icons.edit_outlined,
                                              color: Colors.white
                                                  .withValues(alpha: 0.4),
                                              size: 18),
                                          onPressed: () =>
                                              _showEditMetadataDialog(
                                                  selectedDevice),
                                          tooltip: 'Edit Vehicle',
                                        ),
                                    ],
                                  ),
                                  Divider(
                                      color:
                                          Colors.white.withValues(alpha: 0.06),
                                      height: 20),
                                  // Telemetry grid
                                  Row(
                                    children: [
                                      Expanded(
                                          child: _buildTelemetryTile(
                                              Icons.speed_rounded,
                                              'Speed',
                                              '${selectedDevice.speed.toStringAsFixed(1)} km/h')),
                                      Expanded(
                                          child: _buildTelemetryTile(
                                              Icons.explore_rounded,
                                              'Bearing',
                                              '${selectedDevice.direction.toStringAsFixed(0)}°')),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                          child: _buildTelemetryTile(
                                              Icons.cloud_outlined,
                                              'Altitude',
                                              '${selectedDevice.altitude.toStringAsFixed(0)}m')),
                                      Expanded(
                                          child: _buildTelemetryTile(
                                              Icons.schedule_rounded,
                                              'GPS Time',
                                              selectedDevice.gpsTime
                                                  .split(' ')
                                                  .last)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  // Coordinates bar
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.04),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceAround,
                                      children: [
                                        Text(
                                          'Lat: ${selectedDevice.latitude.toStringAsFixed(5)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            color: Colors.white
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                        Text(
                                          'Lon: ${selectedDevice.longitude.toStringAsFixed(5)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            color: Colors.white
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selectedDevice.additionalData != null &&
                                      selectedDevice
                                          .additionalData!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: selectedDevice
                                          .additionalData!.entries
                                          .map((entry) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.04),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '${entry.key}: ${entry.value}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: theme.colorScheme.primary
                                                  .withValues(alpha: 0.8),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 20, horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141B2D)
                                .withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Text(
                              devices.isEmpty
                                  ? 'Waiting for active devices to connect...'
                                  : 'Select a vehicle above to focus on map',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontStyle: FontStyle.italic,
                                fontSize: 13,
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
        ],
      ),
    );
  }

  Color? _parseColor(String colorStr) {
    try {
      if (colorStr.startsWith('#')) {
        String cleanHex = colorStr.replaceAll('#', '');
        if (cleanHex.length == 6) cleanHex = 'FF$cleanHex';
        return Color(int.parse(cleanHex, radix: 16));
      }
      final map = {
        'red': Colors.redAccent,
        'blue': Colors.blueAccent,
        'green': Colors.greenAccent,
        'cyan': Colors.cyanAccent,
        'orange': Colors.orangeAccent,
        'yellow': Colors.yellowAccent,
        'purple': Colors.purpleAccent,
      };
      return map[colorStr.toLowerCase()];
    } catch (e) {
      return null;
    }
  }

  String _formatElapsedTime(DateTime lastUpdated) {
    final difference = DateTime.now().difference(lastUpdated);
    if (difference.inSeconds < 5) {
      return 'Just now';
    } else if (difference.inMinutes < 1) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inHours < 1) {
      final minutes = difference.inMinutes;
      final seconds = difference.inSeconds % 60;
      return '${minutes}m ${seconds}s ago';
    } else {
      final hours = difference.inHours;
      final minutes = difference.inMinutes % 60;
      return '${hours}h ${minutes}m ago';
    }
  }

  Widget _buildTelemetryTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 15,
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.7)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
              ),
              Text(
                value,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
