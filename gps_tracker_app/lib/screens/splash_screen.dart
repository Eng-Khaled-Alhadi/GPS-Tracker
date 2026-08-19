import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../providers/gps_provider.dart';
import 'login_screen.dart';
import 'main_navigation_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  String _statusText = 'Initializing satellite telemetry...';

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _fadeController.forward();
    _initializeApp();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    final startTime = DateTime.now();
    final provider = Provider.of<GPSProvider>(context, listen: false);

    // 1. Update status step
    if (!kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 400));
    }
    if (mounted) {
      setState(() {
        _statusText = 'Loading fleet coordinates...';
      });
    }

    // 2. Load saved session from secure storage
    final bool hasValidSession = await provider.loadSavedSession();

    if (mounted) {
      setState(() {
        _statusText = 'Ready';
      });
    }

    // 3. Ensure a minimum splash screen duration on mobile for smooth visual experience
    if (!kIsWeb) {
      final elapsed = DateTime.now().difference(startTime);
      final remaining = const Duration(milliseconds: 2000) - elapsed;
      if (remaining > Duration.zero) {
        await Future.delayed(remaining);
      }
    }

    if (!mounted) return;

    // 4. Smooth page transition
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) {
          return hasValidSession
              ? const MainNavigationScreen()
              : const LoginScreen();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bgGradient = RadialGradient(
      center: Alignment.center,
      radius: 1.1,
      colors: [Color(0xFF1E293B), Color(0xFF0F172A), Color(0xFF070B14)],
    );

    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: Container(
        decoration: const BoxDecoration(gradient: bgGradient),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Clean High-Tech Lottie Radar Animation
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: Lottie.asset(
                      'assets/animations/radar_splash.json',
                      width: 260,
                      height: 260,
                      fit: BoxFit.contain,
                      repeat: true,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Brand Title
                  RichText(
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: 'QUT',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                            color: Colors.white,
                          ),
                        ),
                        TextSpan(
                          text: 'MA',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                            color: Color(0xFF00E5FF),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    'GPS FLEET TRACKING & TELEMETRY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.2,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Loading Pulse Indicator & Status text
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.cyanAccent.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF00E5FF),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
