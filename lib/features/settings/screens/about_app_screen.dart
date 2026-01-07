import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.primaryRed,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'About App',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/cradi_logo.jpg',
                width: 120,
                height: 120,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.shield,
                  size: 100,
                  color: AppColors.primaryRed,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'CRADI Mobile',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Early Warning System',
                style: GoogleFonts.lexend(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Version 2.4.1 (Build 204)',
                  style: GoogleFonts.lexend(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              Text(
                '© 2024 CRADI. All rights reserved.',
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () {},
                    child: Text(
                      'Privacy Policy',
                      style: GoogleFonts.lexend(color: AppColors.primaryRed),
                    ),
                  ),
                  Text('•', style: TextStyle(color: Colors.grey.shade400)),
                  TextButton(
                    onPressed: () {},
                    child: Text(
                      'Terms of Service',
                      style: GoogleFonts.lexend(color: AppColors.primaryRed),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
