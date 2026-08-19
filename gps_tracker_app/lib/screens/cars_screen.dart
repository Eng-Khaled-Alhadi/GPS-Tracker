import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../providers/gps_provider.dart';

class CarsScreen extends StatefulWidget {
  const CarsScreen({super.key});

  @override
  State<CarsScreen> createState() => _CarsScreenState();
}

class _CarsScreenState extends State<CarsScreen> {
  Timer? _uiTimer;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<GPSProvider>(context, listen: false).fetchDevices();
    });
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  void _showEditMetadataDialog(GPSProvider provider, Device device) {
    if (provider.currentRole == 'viewer') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permission Denied: Viewer role cannot edit vehicle settings.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final nameController = TextEditingController(text: device.name ?? '');
    final colorController = TextEditingController(text: device.color ?? '');
    final typeController = TextEditingController(text: device.carType ?? '');

    final List<MapEntry<TextEditingController, TextEditingController>> customFields = [];
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
                        hintText: 'e.g. Delivery Van 01',
                        prefixIcon: Icon(Icons.label_outline, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: colorController,
                      decoration: const InputDecoration(
                        labelText: 'Color (Hex or name)',
                        hintText: 'e.g. #3B82F6 or blue',
                        prefixIcon: Icon(Icons.palette_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: typeController,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Type',
                        hintText: 'e.g. Sedan, SUV, Truck, Van',
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
                                  hintText: 'Key',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: field.value,
                                decoration: const InputDecoration(
                                  hintText: 'Value',
                                  isDense: true,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              onPressed: () {
                                setDialogState(() => customFields.remove(field));
                              },
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
                    provider.updateDeviceMetadata(
                      deviceId: device.id,
                      name: nameController.text.trim(),
                      color: colorController.text.trim(),
                      carType: typeController.text.trim(),
                      additionalData: extraData,
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _parseColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return const Color(0xFF3B82F6);
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
      return map[colorStr.toLowerCase()] ?? const Color(0xFF3B82F6);
    } catch (e) {
      return const Color(0xFF3B82F6);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GPSProvider>(context);
    final allDevices = provider.devicesList;
    final size = MediaQuery.of(context).size;
    final isWeb = size.width >= 800;

    // Filter
    final devices = _searchQuery.isEmpty
        ? allDevices
        : allDevices.where((d) {
            final q = _searchQuery.toLowerCase();
            return d.displayName.toLowerCase().contains(q) ||
                d.id.toLowerCase().contains(q) ||
                (d.carType ?? '').toLowerCase().contains(q);
          }).toList();

    final onlineCount = allDevices
        .where((d) => DateTime.now().difference(d.lastUpdated).inSeconds < 45)
        .length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(20, isWeb ? 24 : 12, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Fleet Management',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${allDevices.length} vehicles registered • $onlineCount active',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => provider.fetchDevices(),
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh Fleet',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search by car name, device ID or type...',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Vehicle list
            Expanded(
              child: devices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _searchQuery.isNotEmpty
                                ? Icons.search_off_rounded
                                : Icons.directions_car_outlined,
                            size: 48,
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No vehicles match "$_searchQuery"'
                                : 'No registered vehicles found in system',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        isWeb ? 24 : 100,
                      ),
                      itemCount: devices.length,
                      itemBuilder: (context, index) =>
                          _buildVehicleCard(provider, devices[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleCard(GPSProvider provider, Device device) {
    final isRecentlyUpdated =
        DateTime.now().difference(device.lastUpdated).inSeconds < 45;
    final customColor = _parseColor(device.color);
    final elapsed = DateTime.now().difference(device.lastUpdated);
    final timeAgo = elapsed.inMinutes < 1
        ? '${elapsed.inSeconds}s ago'
        : elapsed.inHours < 1
            ? '${elapsed.inMinutes}m ago'
            : '${elapsed.inHours}h ago';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Accent Line
            Container(
              height: 3,
              color: customColor,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Vehicle info & Status badge + Edit
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: customColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.directions_car_rounded,
                          color: customColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: ${device.id}${device.carType != null && device.carType!.isNotEmpty ? ' • ${device.carType}' : ''}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (isRecentlyUpdated
                                  ? const Color(0xFF10B981)
                                  : Colors.white.withValues(alpha: 0.1))
                              .withValues(alpha: isRecentlyUpdated ? 0.15 : 1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isRecentlyUpdated
                                    ? const Color(0xFF10B981)
                                    : Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isRecentlyUpdated ? 'Online' : 'Offline',
                              style: TextStyle(
                                color: isRecentlyUpdated
                                    ? const Color(0xFF10B981)
                                    : Colors.white.withValues(alpha: 0.45),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (provider.currentRole != 'viewer')
                        IconButton(
                          icon: Icon(
                            Icons.edit_outlined,
                            color: Colors.white.withValues(alpha: 0.4),
                            size: 18,
                          ),
                          onPressed: () => _showEditMetadataDialog(provider, device),
                          tooltip: 'Edit Vehicle',
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Row 2: Telemetry Metrics
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMetric(
                          Icons.speed_rounded,
                          '${device.speed.toStringAsFixed(1)} km/h',
                          'Speed',
                        ),
                        _buildMetric(
                          Icons.location_on_outlined,
                          '${device.latitude.toStringAsFixed(4)}, ${device.longitude.toStringAsFixed(4)}',
                          'Location',
                        ),
                        _buildMetric(
                          Icons.access_time_rounded,
                          timeAgo,
                          'Updated',
                        ),
                      ],
                    ),
                  ),

                  // Row 3: Admin Approval Switch if disabled
                  if (provider.currentRole == 'admin' && !device.enabled) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Pending Approval',
                            style: TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            const Text(
                              'Enable on Map:',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            const SizedBox(width: 6),
                            Switch(
                              value: device.enabled,
                              onChanged: (val) =>
                                  provider.toggleDeviceEnabled(device.id, val),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(IconData icon, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.white.withValues(alpha: 0.35)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
