import 'package:flutter/material.dart';
import 'package:gps_tracker_app/providers/gps_provider.dart';
import 'package:provider/provider.dart';
import 'screens/login_screen.dart';

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
    final isDark = gpsProvider.isDarkTheme;
    final accentColor = gpsProvider.accentColor;

    final baseTheme = isDark ? ThemeData.dark() : ThemeData.light();
    final scaffoldBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return MaterialApp(
      title: 'Active GPS Fleet Tracker',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: scaffoldBg,
        textTheme: baseTheme.textTheme.apply(
          bodyColor: textColor,
          displayColor: textColor,
        ),
        colorScheme: isDark
            ? ColorScheme.dark(
                primary: accentColor,
                secondary: const Color(0xFF10B981),
                surface: cardBg,
                background: scaffoldBg,
                error: const Color(0xFFEF4444),
              )
            : ColorScheme.light(
                primary: accentColor,
                secondary: const Color(0xFF10B981),
                surface: cardBg,
                background: scaffoldBg,
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
      home: const LoginScreen(),
    );
  }
}
