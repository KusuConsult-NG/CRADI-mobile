import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/design/glass_container.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Background - clean or subtle pattern
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.background, AppColors.surface],
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 60),

                  // Logo
                  Center(
                    child: GlassContainer(
                      width: 120,
                      height: 120,
                      borderRadius: 60,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/ewer_logo.jpg',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.security,
                                  size: 50,
                                  color: AppColors.primaryRed,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // App Name & Tagline
                  Text(
                    'Welcome to EWER',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lexend(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Early Warning and Early Response System',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lexend(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Empowering communities with real-time hazard reporting and rapid response coordination.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.roboto(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 60),

                  // Main Actions
                  GlassCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Get Started',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lexend(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 24),

                        CustomButton(
                          text: 'Sign Up',
                          onPressed: () => context.push('/register'),
                          icon: Icons.person_add_outlined,
                        ),

                        const SizedBox(height: 16),

                        CustomButton(
                          text: 'Login',
                          type: ButtonType.secondary,
                          onPressed: () => context.push('/login'),
                          icon: Icons.login,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Footer / Copyright
                  Text(
                    '© ${DateTime.now().year} CRADI. All rights reserved.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.roboto(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
