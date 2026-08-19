import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/gps_provider.dart';
import '../models/overspeed_alert.dart';
import 'dashboard_screen.dart';
import 'cars_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  int _currentIndex = 0;
  StreamSubscription<OverspeedAlert>? _alertSubscription;

  // Banner properties
  OverspeedAlert? _activeBannerAlert;
  late AnimationController _bannerAnimController;
  late Animation<Offset> _bannerSlideAnimation;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);

    // Setup animated banner controller
    _bannerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _bannerSlideAnimation =
        Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _bannerAnimController,
            curve: Curves.easeOutBack,
          ),
        );

    // Listen to overspeed alerts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<GPSProvider>(context, listen: false);
      _alertSubscription = provider.alertStream.listen((alert) {
        _triggerAlertBanner(alert);
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _alertSubscription?.cancel();
    _bannerAnimController.dispose();
    _bannerTimer?.cancel();
    super.dispose();
  }

  void _triggerAlertBanner(OverspeedAlert alert) {
    _bannerTimer?.cancel();
    setState(() {
      _activeBannerAlert = alert;
    });
    _bannerAnimController.forward();

    // Dismiss banner after 4 seconds
    _bannerTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        _bannerAnimController.reverse().then((_) {
          if (mounted) {
            setState(() {
              _activeBannerAlert = null;
            });
          }
        });
      }
    });
  }

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<GPSProvider>(context);
    final size = MediaQuery.of(context).size;
    final isWeb = size.width >= 800;
    final theme = Theme.of(context);

    // Screen list
    final List<Widget> screens = [
      const GPSDashboard(),
      const CarsScreen(),
      HistoryScreen(
        serverAddress: provider.serverAddress,
        token: provider.token,
      ),
      const SettingsScreen(),
    ];

    // Navigation Tab Data
    final List<Map<String, dynamic>> navItems = [
      {'icon': Icons.map, 'label': 'Map'},
      {'icon': Icons.directions_car, 'label': 'Vehicles'},
      {'icon': Icons.history, 'label': 'History'},
      {
        'icon': Icons.settings,
        'label': 'Settings',
        'badge': provider.unreadAlertsCount > 0
            ? provider.unreadAlertsCount
            : null,
      },
    ];

    // Responsive Web Layout: Left Sidebar Navigation
    Widget webLayout = Row(
      children: [
        SafeArea(
          child: Container(
            width: 90,
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 10,
                  offset: Offset(2, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 24),
                const Icon(Icons.gps_fixed, color: Colors.cyanAccent, size: 28),
                const SizedBox(height: 32),
                Expanded(
                  child: ListView.builder(
                    itemCount: navItems.length,
                    itemBuilder: (context, index) {
                      final item = navItems[index];
                      final isSelected = _currentIndex == index;
                      final badgeCount = item['badge'] as int?;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: InkWell(
                          onTap: () => _onTabSelected(index),
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                                .withValues(alpha: 0.2)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      item['icon'] as IconData,
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : Colors.white60,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item['label'] as String,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white60,
                                      fontSize: 11,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                              if (badgeCount != null)
                                Positioned(
                                  top: 4,
                                  right: 18,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    child: Text(
                                      '$badgeCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: screens,
          ),
        ),
      ],
    );

    // Responsive Mobile Layout: Bottom Samsung One UI Floating Nav Bar
    Widget mobileLayout = Stack(
      children: [
        PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: screens,
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: SafeArea(
            bottom: true,
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(navItems.length, (index) {
                  final item = navItems[index];
                  final isSelected = _currentIndex == index;
                  final badgeCount = item['badge'] as int?;

                  return Expanded(
                    child: InkWell(
                      onTap: () => _onTabSelected(index),
                      borderRadius: BorderRadius.circular(32),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? theme.colorScheme.primary.withValues(
                                          alpha: 0.15,
                                        )
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  item['icon'] as IconData,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : Colors.white60,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item['label'] as String,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white60,
                                  fontSize: 10,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                          if (badgeCount != null)
                            Positioned(
                              top: 6,
                              right: 24,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                child: Text(
                                  '$badgeCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );

    // Render layout with overlays
    return Scaffold(
      body: Stack(
        children: [
          isWeb ? webLayout : mobileLayout,

          // 🚨 Animated Top Warning Banner for Overspeed Events
          if (_activeBannerAlert != null)
            SlideTransition(
              position: _bannerSlideAnimation,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Material(
                      elevation: 10,
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF7F1D1D,
                          ), // Dark One UI deep red warning
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.redAccent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.warning,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'SPEED LIMIT EXCEEDED',
                                    style: TextStyle(
                                      color: Colors.red[100],
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_activeBannerAlert!.deviceName} is driving at ${_activeBannerAlert!.speed.toStringAsFixed(1)} km/h!',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                _bannerAnimController.reverse();
                              },
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
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
        ],
      ),
    );
  }
}
