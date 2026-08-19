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

  void _showCarInfoBottomSheet(BuildContext context, Device device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF141B2D),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (_parseColor(device.color ?? '') ??
                                      Theme.of(context).colorScheme.primary)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.directions_car_rounded,
                              color: _parseColor(device.color ?? '') ??
                                  Theme.of(context).colorScheme.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.displayName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              if (device.carType != null && device.carType!.isNotEmpty)
                                Text(
                                  device.carType!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.4)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Divider(color: Colors.white.withValues(alpha: 0.06), height: 28),
                  _buildDetailRow(Icons.speed_rounded, 'Speed',
                      '${device.speed.toStringAsFixed(1)} km/h'),
                  _buildDetailRow(Icons.explore_rounded, 'Direction',
                      '${device.direction.toStringAsFixed(0)}°'),
                  _buildDetailRow(Icons.landscape_rounded, 'Altitude',
                      '${device.altitude.toStringAsFixed(0)}m'),
                  _buildDetailRow(Icons.access_time_rounded, 'GPS Time',
                      device.gpsTime),
                  _buildDetailRow(Icons.my_location_rounded, 'Coordinates',
                      '${device.latitude.toStringAsFixed(6)}, ${device.longitude.toStringAsFixed(6)}'),
                  if (device.additionalData != null &&
                      device.additionalData!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'METADATA',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...device.additionalData!.entries.map(
                      (entry) => _buildDetailRow(
                        Icons.info_outline_rounded,
                        entry.key,
                        entry.value.toString(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.3), size: 17),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
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

  void _showServerConfigDialog(GPSProvider provider) {
    final controller = TextEditingController(text: provider.serverAddress);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Server Configuration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter WebSocket server URL',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'WebSocket URL',
                  hintText: 'wss://tracking.qutma.com/ws',
                  prefixIcon: Icon(Icons.link_rounded),
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
                provider.initializeSession(
                  role: provider.currentRole,
                  username: provider.currentUsername,
                  serverUrl: controller.text.trim(),
                  token: provider.token,
                );
                Navigator.pop(context);
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }

  void _showAdminSettingsDialog(GPSProvider provider) {
    provider.fetchUsers();

    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'viewer';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return DefaultTabController(
              length: 2,
              child: AlertDialog(
                title: const Text('Admin Panel'),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                content: SizedBox(
                  width: 500,
                  height: 420,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(icon: Icon(Icons.manage_accounts_outlined),
                              text: 'Users'),
                          Tab(icon: Icon(Icons.palette_outlined),
                              text: 'Theme'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // Users Tab
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ExpansionTile(
                                  title: const Text('Add New User',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        children: [
                                          TextField(
                                            controller: usernameController,
                                            decoration: const InputDecoration(
                                              labelText: 'Username',
                                              isDense: true,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: passwordController,
                                            obscureText: true,
                                            decoration: const InputDecoration(
                                              labelText: 'Password',
                                              isDense: true,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          DropdownButtonFormField<String>(
                                            initialValue: selectedRole,
                                            decoration: const InputDecoration(
                                              labelText: 'Role',
                                              isDense: true,
                                            ),
                                            items: const [
                                              DropdownMenuItem(
                                                  value: 'admin',
                                                  child: Text('Admin')),
                                              DropdownMenuItem(
                                                  value: 'editor',
                                                  child: Text('Editor')),
                                              DropdownMenuItem(
                                                  value: 'viewer',
                                                  child: Text('Viewer')),
                                            ],
                                            onChanged: (val) {
                                              if (val != null) {
                                                setDialogState(
                                                    () => selectedRole = val);
                                              }
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                          ElevatedButton(
                                            onPressed: () {
                                              final user =
                                                  usernameController.text.trim();
                                              final pass =
                                                  passwordController.text;
                                              if (user.isNotEmpty &&
                                                  pass.isNotEmpty) {
                                                provider.createUser(
                                                    user, pass, selectedRole);
                                                usernameController.clear();
                                                passwordController.clear();
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(SnackBar(
                                                  content: Text(
                                                      'Creating user "$user"...'),
                                                ));
                                              }
                                            },
                                            child: const Text('Add User'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  child: Text(
                                    'Existing Users',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Colors.white.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: provider.users.isEmpty
                                      ? Center(
                                          child: Text('Loading...',
                                              style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.3))))
                                      : ListView.builder(
                                          itemCount: provider.users.length,
                                          itemBuilder: (context, index) {
                                            final u = provider.users[index];
                                            final isSelf = u['username'] ==
                                                provider.currentUsername;
                                            return ListTile(
                                              title:
                                                  Text(u['username'] ?? ''),
                                              subtitle: Text(
                                                  'Role: ${u['role']}'),
                                              dense: true,
                                              trailing: isSelf
                                                  ? Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 8,
                                                          vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                            .withValues(
                                                                alpha: 0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                      ),
                                                      child: Text('You',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .primary,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700,
                                                          )),
                                                    )
                                                  : IconButton(
                                                      icon: const Icon(
                                                          Icons.delete_outline,
                                                          color:
                                                              Colors.redAccent,
                                                          size: 20),
                                                      onPressed: () {
                                                        provider.deleteUser(
                                                            u['id']);
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                                'Deleting "${u['username']}"...'),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                            // Theme Tab
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Divider(height: 32),
                                  Text(
                                    'Accent Color',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: Colors.white.withValues(alpha: 0.8),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _colorDot(provider, Colors.blueAccent, 'Blue'),
                                      _colorDot(provider, Colors.greenAccent, 'Green'),
                                      _colorDot(provider, Colors.orangeAccent, 'Orange'),
                                      _colorDot(provider, Colors.purpleAccent, 'Purple'),
                                      _colorDot(provider, Colors.redAccent, 'Red'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _colorDot(GPSProvider provider, Color color, String name) {
    final isSelected = provider.accentColor.toARGB32() == color.toARGB32();
    return GestureDetector(
      onTap: () => provider.setAccentColor(color),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 3,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
          ],
        ),
      ),
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

          // === Top Status Chip ===
          Positioned(
            top: isWeb ? 16 : 50,
            left: 16,
            child: Row(
              children: [
                // Connection chip
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
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
                                    ? 'Reconnecting'
                                    : 'Offline',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            ' • ${provider.currentUsername}',
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
                if (provider.currentRole == 'admin') ...[
                  const SizedBox(width: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Material(
                        color: const Color(0xFF0F1523).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () => _showAdminSettingsDialog(provider),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.06)),
                            ),
                            child: const Icon(Icons.admin_panel_settings_outlined,
                                color: Colors.amber, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // === Auto-follow toggle ===
          Positioned(
            top: isWeb ? 16 : 50,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Material(
                  color: provider.autoFollow
                      ? theme.colorScheme.primary
                      : const Color(0xFF0F1523).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () {
                      provider.setAutoFollow(!provider.autoFollow);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Icon(
                        provider.autoFollow
                            ? Icons.gps_fixed_rounded
                            : Icons.gps_not_fixed_rounded,
                        color: Colors.white,
                        size: 20,
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
                      // Device selector chips
                      if (devices.isNotEmpty)
                        SizedBox(
                          height: 48,
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
                                      horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : const Color(0xFF141B2D)
                                            .withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : Colors.white
                                              .withValues(alpha: 0.06),
                                    ),
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
                                                  .withValues(alpha: 0.2),
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
                                                      .withValues(alpha: 0.8),
                                            ),
                                          ),
                                          Text(
                                            '${device.speed.toStringAsFixed(1)} km/h',
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Colors.white
                                                      .withValues(alpha: 0.7)
                                                  : Colors.white
                                                      .withValues(alpha: 0.35),
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
                                    .withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.06)),
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
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(Icons.sensors_rounded,
                                            color: theme.colorScheme.primary,
                                            size: 18),
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
                                            if (selectedDevice.carType != null &&
                                                selectedDevice.carType!
                                                    .trim()
                                                    .isNotEmpty)
                                              Text(
                                                selectedDevice.carType!,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.35),
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
                                              .withValues(alpha: 0.3),
                                          fontSize: 11,
                                        ),
                                      ),
                                      if (provider.currentRole != 'viewer')
                                        IconButton(
                                          icon: Icon(Icons.edit_outlined,
                                              color: Colors.white
                                                  .withValues(alpha: 0.3),
                                              size: 17),
                                          onPressed: () =>
                                              _showEditMetadataDialog(
                                                  selectedDevice),
                                        ),
                                    ],
                                  ),
                                  Divider(
                                      color:
                                          Colors.white.withValues(alpha: 0.06),
                                      height: 22),
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
                                              'Time',
                                              selectedDevice.gpsTime
                                                  .split(' ')
                                                  .last)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  // Coordinates bar
                                  Container(
                                    padding: const EdgeInsets.all(10),
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
                                          'Lat: ${selectedDevice.latitude.toStringAsFixed(6)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            color: Colors.white
                                                .withValues(alpha: 0.5),
                                          ),
                                        ),
                                        Text(
                                          'Lon: ${selectedDevice.longitude.toStringAsFixed(6)}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            color: Colors.white
                                                .withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selectedDevice.additionalData != null &&
                                      selectedDevice
                                          .additionalData!.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: selectedDevice
                                          .additionalData!.entries
                                          .map((entry) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
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
                              vertical: 24, horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141B2D)
                                .withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Text(
                              devices.isEmpty
                                  ? 'Waiting for devices to connect...'
                                  : 'Select a vehicle to view details',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontStyle: FontStyle.italic,
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
                  .withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
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
