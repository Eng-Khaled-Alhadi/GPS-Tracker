import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../providers/gps_provider.dart';
import 'history_screen.dart';
import 'cars_screen.dart';

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
      if (mounted) {
        setState(() {});
      }
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
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white10),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: SafeArea(
            // mainAxisSize: MainAxisSize.min,
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
                          Icon(
                            Icons.directions_car,
                            color:
                                _parseColor(device.color ?? '') ??
                                Colors.cyanAccent,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            device.displayName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    Icons.speed,
                    'Speed',
                    '${device.speed.toStringAsFixed(1)} km/h',
                  ),
                  _buildDetailRow(
                    Icons.explore,
                    'Direction',
                    '${device.direction.toStringAsFixed(0)}°',
                  ),
                  _buildDetailRow(
                    Icons.landscape,
                    'Altitude',
                    '${device.altitude.toStringAsFixed(0)}m',
                  ),
                  _buildDetailRow(
                    Icons.access_time,
                    'GPS Time',
                    device.gpsTime,
                  ),
                  _buildDetailRow(
                    Icons.my_location,
                    'Coordinates',
                    '${device.latitude.toStringAsFixed(6)}, ${device.longitude.toStringAsFixed(6)}',
                  ),
                  if (device.additionalData != null &&
                      device.additionalData!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Additional Metadata',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.cyanAccent,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...device.additionalData!.entries.map(
                      (entry) => _buildDetailRow(
                        Icons.info_outline,
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.white60, size: 18),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
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
          content: Text(
            'Permission Denied: Viewer role cannot edit car settings.',
          ),
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
        customFields.add(
          MapEntry(
            TextEditingController(text: key),
            TextEditingController(text: value.toString()),
          ),
        );
      });
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit Config: ${device.id}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Car Display Name',
                        hintText: 'e.g. CEO Sedan',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: colorController,
                      decoration: const InputDecoration(
                        labelText: 'Display Color (Hex or name)',
                        hintText: 'e.g. #FF0000 or red',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: typeController,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Type',
                        hintText: 'e.g. Sedan, SUV, Van',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Custom Attributes:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              customFields.add(
                                MapEntry(
                                  TextEditingController(),
                                  TextEditingController(),
                                ),
                              );
                            });
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text(
                            'Add Key',
                            style: TextStyle(fontSize: 11),
                          ),
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
                                Icons.delete,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  customFields.remove(field);
                                });
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
                      if (k.isNotEmpty) {
                        extraData[k] = v;
                      }
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
              const Text(
                'Enter WebSocket server URL (e.g. wss://tracking.qutma.com/ws or ws://ip:8081).',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'WebSocket URL',
                  hintText: 'wss://tracking.qutma.com/ws',
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
                title: const Text('Admin Panel & Settings'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 16,
                ),
                content: SizedBox(
                  width: 500,
                  height: 420,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(
                            icon: Icon(Icons.manage_accounts),
                            text: 'Users Manager',
                          ),
                          Tab(
                            icon: Icon(Icons.palette),
                            text: 'Theme Settings',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // 1. Users Manager Tab
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ExpansionTile(
                                  title: const Text(
                                    'Add New User',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
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
                                                child: Text('Admin'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'editor',
                                                child: Text('Editor'),
                                              ),
                                              DropdownMenuItem(
                                                value: 'viewer',
                                                child: Text('Viewer'),
                                              ),
                                            ],
                                            onChanged: (val) {
                                              if (val != null) {
                                                setDialogState(() {
                                                  selectedRole = val;
                                                });
                                              }
                                            },
                                          ),
                                          const SizedBox(height: 12),
                                          ElevatedButton(
                                            onPressed: () {
                                              final user = usernameController
                                                  .text
                                                  .trim();
                                              final pass =
                                                  passwordController.text;
                                              if (user.isNotEmpty &&
                                                  pass.isNotEmpty) {
                                                provider.createUser(
                                                  user,
                                                  pass,
                                                  selectedRole,
                                                );
                                                usernameController.clear();
                                                passwordController.clear();
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Creating user "$user"...',
                                                    ),
                                                  ),
                                                );
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
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    'Existing Users:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: provider.users.isEmpty
                                      ? const Center(
                                          child: Text(
                                            'Loading users...',
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: provider.users.length,
                                          itemBuilder: (context, index) {
                                            final u = provider.users[index];
                                            final isSelf =
                                                u['username'] ==
                                                provider.currentUsername;
                                            return ListTile(
                                              title: Text(u['username'] ?? ''),
                                              subtitle: Text(
                                                'Role: ${u['role']}',
                                              ),
                                              dense: true,
                                              trailing: isSelf
                                                  ? const Chip(
                                                      label: Text(
                                                        'You',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                    )
                                                  : IconButton(
                                                      icon: const Icon(
                                                        Icons.delete,
                                                        color: Colors.redAccent,
                                                        size: 20,
                                                      ),
                                                      onPressed: () {
                                                        provider.deleteUser(
                                                          u['id'],
                                                        );
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              'Deleting user "${u['username']}"...',
                                                            ),
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

                            // 2. Theme Settings Tab
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // const Text(
                                  //   'Theme Mode',
                                  //   style: TextStyle(
                                  //     fontWeight: FontWeight.bold,
                                  //     fontSize: 15,
                                  //   ),
                                  // ),
                                  // const SizedBox(height: 8),
                                  // SwitchListTile(
                                  //   title: const Text('Dark Mode'),
                                  //   value: provider.isDarkTheme,
                                  //   onChanged: (val) {
                                  //     provider.toggleTheme(val);
                                  //   },
                                  // ),
                                  const Divider(height: 32),
                                  const Text(
                                    'Accent Color',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _colorDot(
                                        provider,
                                        Colors.blueAccent,
                                        'Blue',
                                      ),
                                      _colorDot(
                                        provider,
                                        Colors.greenAccent,
                                        'Green',
                                      ),
                                      _colorDot(
                                        provider,
                                        Colors.orangeAccent,
                                        'Orange',
                                      ),
                                      _colorDot(
                                        provider,
                                        Colors.purpleAccent,
                                        'Purple',
                                      ),
                                      _colorDot(
                                        provider,
                                        Colors.redAccent,
                                        'Red',
                                      ),
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

    // Auto-follow logic
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
          // 1. Map Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: selectedDevice != null
                  ? LatLng(selectedDevice.latitude, selectedDevice.longitude)
                  : const LatLng(24.573213, 46.546881), // Default Riyadh
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
                      strokeWidth: 4.0,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: devices.map((device) {
                  final isSelected =
                      device.id ==
                      (selectedDevice?.id ?? provider.selectedDeviceId);
                  final angle = (device.direction * math.pi) / 180.0;

                  Color arrowColor = isSelected
                      ? const Color(0xFF3B82F6)
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
                          if (device.name != null &&
                              device.name!.trim().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              margin: const EdgeInsets.only(bottom: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                device.name!,
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: Colors.cyanAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blue
                                  : const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white24,
                                width: 1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              '${device.speed.toStringAsFixed(1)} km/h',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Transform.rotate(
                            angle: angle,
                            child: Icon(
                              Icons.navigation,
                              size: isSelected ? 32 : 24,
                              color: arrowColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: arrowColor,
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

          // 2. Premium Top Bar Overlay
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF0F172A,
                            ).withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black54,
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: provider.isConnected
                                      ? Colors.green
                                      : provider.isConnecting
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
                                      provider.isConnected
                                          ? 'Connected Live (${provider.currentUsername} - ${provider.currentRole.toUpperCase()})'
                                          : provider.isConnecting
                                          ? 'Reconnecting...'
                                          : 'Disconnected',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      provider.serverAddress,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              // IconButton(
                              //   icon: const Icon(
                              //     Icons.settings,
                              //     color: Colors.blue,
                              //   ),
                              //   onPressed: () =>
                              //       _showServerConfigDialog(provider),
                              //   tooltip: 'Server Settings',
                              // ),
                              if (provider.currentRole == 'admin') ...[
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(
                                    Icons.admin_panel_settings,
                                    color: Colors.amber,
                                  ),
                                  onPressed: () =>
                                      _showAdminSettingsDialog(provider),
                                  tooltip: 'Admin Settings',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),
                      FloatingActionButton.small(
                        heroTag: 'btnAutoFollow',
                        backgroundColor: provider.autoFollow
                            ? Colors.blue
                            : const Color(0xFF0F172A),
                        onPressed: () {
                          provider.setAutoFollow(!provider.autoFollow);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                !provider.autoFollow
                                    ? 'Auto-follow Device Disabled'
                                    : 'Auto-follow Device Enabled',
                              ),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Icon(
                          provider.autoFollow
                              ? Icons.gps_fixed
                              : Icons.gps_not_fixed,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. Center/Constrained Bottom Sheet
          Positioned(
            bottom: MediaQuery.of(context).size.width >= 800 ? 24 : 105,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (devices.isNotEmpty)
                        SizedBox(
                          height: 55,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: devices.map((device) {
                              final isSelected =
                                  device.id ==
                                  (selectedDevice?.id ??
                                      provider.selectedDeviceId);
                              final isRecentlyUpdated =
                                  DateTime.now()
                                      .difference(device.lastUpdated)
                                      .inSeconds <
                                  30;

                              return GestureDetector(
                                onTap: () => _focusDevice(provider, device),
                                onLongPress: () =>
                                    _showEditMetadataDialog(device),
                                child: Tooltip(
                                  message:
                                      'Long press to edit vehicle configuration',
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF1D4ED8)
                                          : const Color(
                                              0xFF1E293B,
                                            ).withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.blue
                                            : Colors.white10,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.directions_car,
                                          color: isRecentlyUpdated
                                              ? Colors.orangeAccent
                                              : Colors.grey,
                                          size: 18,
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
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                            Text(
                                              '${device.speed.toStringAsFixed(1)} km/h',
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 9,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (selectedDevice != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1E293B,
                            ).withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white10),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black54,
                                blurRadius: 15,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.sensors,
                                          color: Colors.orangeAccent,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'car: ${selectedDevice.displayName}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  letterSpacing: 0.5,
                                                  color: Colors.white,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (selectedDevice.carType !=
                                                      null &&
                                                  selectedDevice.carType!
                                                      .trim()
                                                      .isNotEmpty)
                                                Text(
                                                  'Type: ${selectedDevice.carType}',
                                                  style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blueAccent,
                                            size: 18,
                                          ),
                                          onPressed: () =>
                                              _showEditMetadataDialog(
                                                selectedDevice,
                                              ),
                                          tooltip: 'Edit Car Properties',
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    'Updated ${_formatElapsedTime(selectedDevice.lastUpdated)}',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white10, height: 20),
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
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    Text(
                                      'Lat: ${selectedDevice.latitude.toStringAsFixed(6)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    Text(
                                      'Lon: ${selectedDevice.longitude.toStringAsFixed(6)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selectedDevice.additionalData != null &&
                                  selectedDevice
                                      .additionalData!
                                      .isNotEmpty) ...[
                                const SizedBox(height: 12),
                                const Text(
                                  'ADDITIONAL DATA',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const Divider(
                                  color: Colors.white10,
                                  height: 10,
                                ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: selectedDevice
                                      .additionalData!
                                      .entries
                                      .map((entry) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.05,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: Colors.white10,
                                            ),
                                          ),
                                          child: Text(
                                            '${entry.key}: ${entry.value}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.cyanAccent,
                                            ),
                                          ),
                                        );
                                      })
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 24,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1E293B,
                            ).withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Center(
                            child: Text(
                              'Waiting for active devices to connect...',
                              style: TextStyle(
                                color: Colors.grey,
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
        if (cleanHex.length == 6) {
          cleanHex = 'FF$cleanHex';
        }
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.blueAccent),
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
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}
