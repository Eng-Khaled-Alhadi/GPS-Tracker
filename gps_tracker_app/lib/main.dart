import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gps_tracker_app/providers/gps_provider.dart';
import 'package:provider/provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    // Only rebuild MaterialApp when accentColor changes, NOT on every GPS telemetry update!
    return Selector<GPSProvider, Color>(
      selector: (_, provider) => provider.accentColor,
      builder: (context, accentColor, child) {
        final baseTheme = ThemeData.dark();
        const scaffoldBg = Color(0xFF0F172A);
        const cardBg = Color(0xFF1E293B);
        const textColor = Colors.white;

        return MaterialApp(
          title: 'QUTMA - GPS Fleet Tracker',
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
          home: const RootAuthRouter(),
        );
      },
    );
  }
}

/// RootAuthRouter runs session loading ONCE in initState,
/// preventing any unexpected page resets on GPS data stream updates.
class RootAuthRouter extends StatefulWidget {
  const RootAuthRouter({super.key});

  @override
  State<RootAuthRouter> createState() => _RootAuthRouterState();
}

class _RootAuthRouterState extends State<RootAuthRouter> {
  late final Future<bool> _sessionFuture;

  @override
  void initState() {
    super.initState();
    _sessionFuture = Provider.of<GPSProvider>(context, listen: false).loadSavedSession();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const SplashScreen();
    }

    return FutureBuilder<bool>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF070B14),
            body: Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            ),
          );
        }
        if (snapshot.data == true) {
          return const MainNavigationScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
