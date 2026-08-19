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
          content: Text('Permission Denied: Viewer role cannot edit car settings.'),
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
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: Colors.redAccent, size: 18),
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
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _parseColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return Colors.blueAccent;
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
      return map[colorStr.toLowerCase()] ?? Colors.blueAccent;
    } catch (e) {
      return Colors.blueAccent;
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Header
          Padding(
            padding: EdgeInsets.fromLTRB(20, isWeb ? 24 : 52, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fleet Vehicles',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${allDevices.length} registered • ${allDevices.where((d) => DateTime.now().difference(d.lastUpdated).inSeconds < 45).length} online',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
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
                hintText: 'Search vehicles...',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
                              : 'No registered vehicles found',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : isWeb
                    ? GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 480,
                          mainAxisExtent: 145,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: devices.length,
                        itemBuilder: (context, index) =>
                            _buildCard(provider, devices[index]),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                        itemCount: devices.length,
                        itemBuilder: (context, index) =>
                            _buildCard(provider, devices[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(GPSProvider provider, Device device) {
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Color accent bar
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: customColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Vehicle icon
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: customColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.directions_car_rounded,
                            color: customColor,
                            size: 20,
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
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'ID: ${device.id}${device.carType != null && device.carType!.isNotEmpty ? ' • ${device.carType}' : ''}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: (isRecentlyUpdated
                                    ? const Color(0xFF10B981)
                                    : Colors.white.withValues(alpha: 0.1))
                                .withValues(alpha: isRecentlyUpdated ? 0.12 : 1),
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
                                      : Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isRecentlyUpdated ? 'Online' : 'Offline',
                                style: TextStyle(
                                  color: isRecentlyUpdated
                                      ? const Color(0xFF10B981)
                                      : Colors.white.withValues(alpha: 0.4),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Actions
                        if (provider.currentRole == 'admin')
                          Switch(
                            value: device.enabled,
                            onChanged: (val) =>
                                provider.toggleDeviceEnabled(device.id, val),
                          ),
                        if (provider.currentRole != 'viewer')
                          IconButton(
                            icon: Icon(
                              Icons.edit_outlined,
                              color: Colors.white.withValues(alpha: 0.35),
                              size: 18,
                            ),
                            onPressed: () =>
                                _showEditMetadataDialog(provider, device),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Stats row
                    Row(
                      children: [
                        _buildStat(
                          Icons.speed_rounded,
                          '${device.speed.toStringAsFixed(1)} km/h',
                        ),
                        const SizedBox(width: 20),
                        _buildStat(
                          Icons.location_on_outlined,
                          '${device.latitude.toStringAsFixed(4)}, ${device.longitude.toStringAsFixed(4)}',
                        ),
                        const Spacer(),
                        if (!device.enabled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Pending',
                              style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Text(
                          timeAgo,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.3)),
        const SizedBox(width: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.55),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
