import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gps_tracker_app/providers/gps_provider.dart';
import 'package:provider/provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/splash_screen.dart';

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
    final accentColor = gpsProvider.accentColor;

    const scaffoldBg = Color(0xFF0A0E1A);
    const cardBg = Color(0xFF141B2D);
    const surfaceBg = Color(0xFF1A2235);
    const textColor = Colors.white;
    const subtextColor = Color(0xFF94A3B8);

    final baseTheme = ThemeData.dark();

    return MaterialApp(
      title: 'QUTMA - GPS Fleet Tracker',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        scaffoldBackgroundColor: scaffoldBg,
        textTheme: baseTheme.textTheme.apply(
          bodyColor: textColor,
          displayColor: textColor,
          fontFamily: 'sans-serif',
        ),
        colorScheme: ColorScheme.dark(
          primary: accentColor,
          secondary: const Color(0xFF10B981),
          surface: cardBg,
          error: const Color(0xFFEF4444),
          onSurface: textColor,
        ),
        cardTheme: CardThemeData(
          color: cardBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
          margin: const EdgeInsets.symmetric(vertical: 6),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: textColor,
            letterSpacing: 0.3,
          ),
          iconTheme: IconThemeData(color: textColor),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: accentColor, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFEF4444)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
          ),
          labelStyle: const TextStyle(color: subtextColor, fontSize: 14),
          hintStyle: TextStyle(color: subtextColor.withValues(alpha: 0.6), fontSize: 14),
          prefixIconColor: subtextColor,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: accentColor,
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
          titleTextStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        dividerTheme: DividerThemeData(
          color: Colors.white.withValues(alpha: 0.06),
          thickness: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: surfaceBg,
          contentTextStyle: const TextStyle(color: textColor, fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          behavior: SnackBarBehavior.floating,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accentColor;
            return subtextColor;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return accentColor.withValues(alpha: 0.3);
            }
            return Colors.white.withValues(alpha: 0.08);
          }),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: accentColor,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
          thumbColor: accentColor,
          overlayColor: accentColor.withValues(alpha: 0.12),
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        ),
      ),
      // On web, skip the in-app splash since index.html pre-loader already handles it
      home: kIsWeb
          ? FutureBuilder<bool>(
              future: Provider.of<GPSProvider>(
                context,
                listen: false,
              ).loadSavedSession(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    backgroundColor: Color(0xFF0A0E1A),
                    body: SizedBox.shrink(),
                  );
                }
                if (snapshot.data == true) {
                  return const MainNavigationScreen();
                }
                return const LoginScreen();
              },
            )
          : const SplashScreen(),
    );
  }
}
