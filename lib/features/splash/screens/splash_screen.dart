import 'package:climate_app/core/providers/settings_provider.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Artificial minimum delay for branding
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    final settingsProvider = context.read<SettingsProvider>();

    if (authProvider.isAuthenticated) {
      if (authProvider.isLocked) {
        // Stay on splash or go to login?
        // Usually if locked, we might go to login screen but in locked state
        // For now, let's go to Login which handles locked state (shows lock screen)
        context.go('/login');
      } else {
        context.go('/dashboard');
      }
    } else {
      if (settingsProvider.hasSeenOnboarding) {
        context.go('/login');
      } else {
        context.go('/onboarding');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/cradi_logo.jpg',
              width: 150,
              height: 150,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Fallback icon if asset missing
                return const Icon(Icons.shield, size: 100, color: Colors.red);
              },
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: Colors.red),
          ],
        ),
      ),
    );
  }
}
