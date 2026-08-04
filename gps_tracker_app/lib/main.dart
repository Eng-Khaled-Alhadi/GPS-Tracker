import 'package:flutter/material.dart';
import 'package:gps_tracker_app/providers/gps_provider.dart';
import 'package:provider/provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/main_navigation_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => GPSProvider())],
      child: const GPSApp(),
    ),
  );
}

class GPSApp extends StatelessWidget {
  const GPSApp({super.key});

  @override
  Widget build(BuildContext context) {
    final gpsProvider = Provider.of<GPSProvider>(context);
    // final isDark = gpsProvider.isDarkTheme;
    final accentColor = gpsProvider.accentColor;

    final baseTheme = ThemeData.dark();
    const scaffoldBg = Color(0xFF0F172A);
    const cardBg = Color(0xFF1E293B);
    const textColor = Colors.white;

    return MaterialApp(
      title: 'Active GPS Fleet Tracker',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: scaffoldBg,
        textTheme: baseTheme.textTheme.apply(
          bodyColor: textColor,
          displayColor: textColor,
        ),
        colorScheme: ColorScheme.dark(
          primary: accentColor,
          secondary: const Color(0xFF10B981),
          surface: cardBg,
          error: const Color(0xFFEF4444),
        ),
        cardTheme: CardThemeData(
          color: cardBg,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: FutureBuilder<bool>(
        future: Provider.of<GPSProvider>(
          context,
          listen: false,
        ).loadSavedSession(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.data == true) {
            return const MainNavigationScreen();
          }
          return const LoginScreen();
        },
      ),
    );
  }
}
