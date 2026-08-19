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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<GPSProvider>(context, listen: false).fetchDevices();
    });
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

  void _showEditMetadataDialog(GPSProvider provider, Device device) {
    if (provider.currentRole == 'viewer') {
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

  Color? _parseColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return null;
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

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GPSProvider>(context);
    final devices = provider.devicesList;
    final size = MediaQuery.of(context).size;
    final isWeb = size.width >= 800;

    Widget buildCard(Device device) {
      final isRecentlyUpdated =
          DateTime.now().difference(device.lastUpdated).inSeconds < 45;
      final customColor = _parseColor(device.color) ?? Colors.blueAccent;
      return Card(
        color: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: customColor.withValues(
                            alpha: 0.2,
                          ),
                          child: Icon(
                            Icons.directions_car,
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
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'ID: ${device.id} • Type: ${device.carType ?? "Not Specified"}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (provider.currentRole == 'admin')
                        Switch(
                          value: device.enabled,
                          activeColor: Colors.greenAccent,
                          inactiveThumbColor: Colors.grey,
                          inactiveTrackColor: Colors.white10,
                          onChanged: (val) {
                            provider.toggleDeviceEnabled(
                              device.id,
                              val,
                            );
                          },
                        ),
                      if (provider.currentRole != 'viewer')
                        IconButton(
                          icon: const Icon(
                            Icons.edit,
                            color: Colors.blueAccent,
                            size: 20,
                          ),
                          onPressed: () => _showEditMetadataDialog(
                            provider,
                            device,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Speed',
                        style: TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                      Text(
                        '${device.speed.toStringAsFixed(1)} km/h',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Coordinates',
                        style: TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                      Text(
                        '${device.latitude.toStringAsFixed(4)}, ${device.longitude.toStringAsFixed(4)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Status',
                        style: TextStyle(color: Colors.grey, fontSize: 10),
                      ),
                      Row(
                        children: [
                          if (!device.enabled)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Pending Approval',
                                style: TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isRecentlyUpdated
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isRecentlyUpdated ? 'Active' : 'Offline',
                            style: TextStyle(
                              color: isRecentlyUpdated
                                  ? Colors.green
                                  : Colors.red,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Registered Vehicles'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: devices.isEmpty
          ? const Center(
              child: Text(
                'No registered vehicles found.',
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          : isWeb
              ? GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 500,
                    mainAxisExtent: 155,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: devices.length,
                  itemBuilder: (context, index) => buildCard(devices[index]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: devices.length,
                  itemBuilder: (context, index) => buildCard(devices[index]),
                ),
    );
  }
}
