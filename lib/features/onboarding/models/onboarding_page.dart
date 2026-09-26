import 'package:flutter/material.dart';
import 'package:climate_app/l10n/app_localizations.dart';

class OnboardingPage {
  final String title;
  final String description;
  final IconData icon;
  final List<Color> gradientColors;

  const OnboardingPage({
    required this.title,
    required this.description,
    required this.icon,
    required this.gradientColors,
  });

  /// The onboarding pages with text in the language of [l10n].
  static List<OnboardingPage> getPages(AppLocalizations l10n) {
    return [
      // Page 1: Welcome - Red to Dark Gray gradient
      OnboardingPage(
        title: l10n.landingWelcome,
        description: l10n.onboardingWelcomeBody,
        icon: Icons.shield_outlined,
        gradientColors: const [
          Color(0xFFE53935), // Bright red from logo
          Color(0xFFB71C1C), // Darker red
          Color(0xFF5D5D5D), // Dark gray from logo
        ],
      ),

      // Page 2: Features - Gray to Red gradient
      OnboardingPage(
        title: l10n.onboardingMonitorTitle,
        description: l10n.onboardingMonitorBody,
        icon: Icons.warning_amber_rounded,
        gradientColors: const [
          Color(0xFF5D5D5D), // Dark gray from logo
          Color(0xFF9E9E9E), // Medium gray
          Color(0xFFE53935), // Bright red from logo
        ],
      ),

      // Page 3: Get Started - Red accent gradient
      OnboardingPage(
        title: l10n.registrationJoinNetwork,
        description: l10n.onboardingJoinBody,
        icon: Icons.people_outline,
        gradientColors: const [
          Color(0xFFB71C1C), // Dark red
          Color(0xFFE53935), // Bright red from logo
          Color(0xFFFF5252), // Lighter red accent
        ],
      ),
    ];
  }
}
