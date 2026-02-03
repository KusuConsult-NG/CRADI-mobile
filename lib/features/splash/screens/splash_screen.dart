import 'dart:ui';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/core/services/onboarding_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _controller.forward();
    _initializeApp();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    // Artificial minimum delay for branding
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    final authProvider = context.read<AuthProvider>();
    final onboardingService = OnboardingService();
    final hasCompletedOnboarding = await onboardingService
        .hasCompletedOnboarding();

    if (!mounted) return;

    // Use addPostFrameCallback to ensure navigation happens after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (authProvider.isAuthenticated) {
        if (authProvider.isLocked) {
          context.go('/login');
        } else {
          context.go('/dashboard');
        }
      } else {
        if (hasCompletedOnboarding) {
          // Returning user (has seen onboarding) → login page
          context.go('/login');
        } else {
          // New user (first launch) → onboarding then registration
          context.go('/onboarding');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFE53935), // Red from logo
              const Color(0xFFB71C1C), // Darker red
              const Color(0xFF5D5D5D), // Gray from logo
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Circular glassmorphic container for logo
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.glassWhite,
                      border: Border.all(
                        color: AppColors.glassBorder,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 40,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(20),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/images/ewer_logo.jpg',
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.shield,
                                  size: 100,
                                  color: Color(0xFFE53935),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // App name with modern styling
                  const Text(
                    'EWER',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 8,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          blurRadius: 20,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Tagline
                  const Text(
                    'Early Warning & Emergency Response',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 60),

                  // Loading indicator
                  const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
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
