import 'package:climate_app/core/design/glass_container.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Spacer(),

              // Logo/Icon
              GlassContainer(
                width: 120,
                height: 120,
                borderRadius: 60,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primaryRed.withValues(alpha: 0.2),
                        AppColors.primaryRed.withValues(alpha: 0.3),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 56,
                    color: AppColors.primaryRed,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // App Name
              Text(
                'EWER',
                style: GoogleFonts.lexend(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                'Early Warning & Emergency Response',
                style: GoogleFonts.lexend(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Description Card
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 40,
                      color: AppColors.primaryRed.withValues(alpha: 0.8),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Community-Powered Early Warning System',
                      style: GoogleFonts.lexend(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Report hazards, receive alerts, and help protect your community from climate risks in Nigeria\'s Middle Belt region.',
                      style: GoogleFonts.lexend(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Key Features
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildFeature(Icons.report_problem, 'Report\nHazards'),
                  _buildFeature(Icons.notifications_active, 'Get\nAlerts'),
                  _buildFeature(Icons.people, 'Help\nCommunity'),
                ],
              ),

              const Spacer(),

              // CTA Buttons
              CustomButton(
                text: 'Create Account',
                onPressed: () => context.go('/register'),
                icon: Icons.person_add,
              ),
              const SizedBox(height: 16),

              CustomButton(
                text: 'Sign In',
                onPressed: () => context.go('/login'),
                type: ButtonType.secondary,
                icon: Icons.login,
              ),
              const SizedBox(height: 24),

              // Footer
              Text(
                'Powered by CRADI • Nigeria',
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeature(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primaryRed.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primaryRed.withValues(alpha: 0.2),
            ),
          ),
          child: Icon(icon, color: AppColors.primaryRed, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.lexend(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
