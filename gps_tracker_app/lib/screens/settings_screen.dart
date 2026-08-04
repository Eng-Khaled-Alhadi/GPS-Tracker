import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/gps_provider.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _speedController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<GPSProvider>(context, listen: false);
      _speedController.text = provider.speedLimit.toStringAsFixed(0);
      provider.markAlertsAsRead();
    });
  }

  @override
  void dispose() {
    _speedController.dispose();
    super.dispose();
  }

  void _updateSpeedLimit(double value, GPSProvider provider) {
    if (value >= 10 && value <= 250) {
      provider.setSpeedLimit(value);
      _speedController.text = value.toStringAsFixed(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GPSProvider>(context);
    final isAdmin = provider.currentRole == 'admin';
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isWeb = size.width >= 800;

    // Build Settings Section
    Widget settingsSection = Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App Settings',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(provider.currentUsername),
                      subtitle: Text('Role: ${provider.currentRole.toUpperCase()}'),
                    ),
                    const Divider(),
                    if (isAdmin) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Speed Limit Alert Threshold (km/h)',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: provider.speedLimit.clamp(10, 250).toDouble(),
                              min: 10,
                              max: 250,
                              divisions: 24,
                              label: '${provider.speedLimit.toStringAsFixed(0)} km/h',
                              onChanged: (val) => _updateSpeedLimit(val, provider),
                            ),
                          ),
                          SizedBox(
                            width: 70,
                            child: TextField(
                              controller: _speedController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (val) {
                                final parsed = double.tryParse(val);
                                if (parsed != null) {
                                  _updateSpeedLimit(parsed, provider);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Alerts trigger when any vehicle exceeds this speed.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await provider.clearSession();
                  if (mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                      (route) => false,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Log Out'),
              ),
            ),
          ],
        ),
      ),
    );

    // Build Alerts Logs Section
    Widget alertsSection = Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Overspeed Logs',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
                if (provider.alerts.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => provider.clearAlerts(),
                    icon: const Icon(
                      Icons.delete_sweep,
                      size: 18,
                      color: Colors.redAccent,
                    ),
                    label: const Text(
                      'Clear All',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: provider.alerts.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 48,
                            color: Colors.green,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'No speeding incidents recorded',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: provider.alerts.length,
                      itemBuilder: (context, index) {
                        final alert = provider.alerts[index];
                        final timeStr =
                            '${alert.timestamp.hour.toString().padLeft(2, '0')}:${alert.timestamp.minute.toString().padLeft(2, '0')}:${alert.timestamp.second.toString().padLeft(2, '0')}';
                        return Card(
                          color: theme.scaffoldBackgroundColor.withValues(
                            alpha: 0.5,
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.speed,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              alert.deviceName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'Speed: ${alert.speed.toStringAsFixed(1)} km/h (Limit: ${alert.limit.toStringAsFixed(0)})',
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: Text(
                              timeStr,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Alerts'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: isWeb
            ? Row(
                children: [
                  Expanded(flex: 4, child: settingsSection),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: alertsSection),
                ],
              )
            : Column(
                children: [
                  Expanded(flex: 4, child: settingsSection),
                  const SizedBox(height: 16),
                  Expanded(flex: 5, child: alertsSection),
                ],
              ),
      ),
    );
  }
}
