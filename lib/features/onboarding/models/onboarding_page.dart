import 'package:flutter/material.dart';

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

  static List<OnboardingPage> getPages() {
    return [
      // Page 1: Welcome - Red to Dark Gray gradient
      const OnboardingPage(
        title: 'Welcome to EWER',
        description:
            'Early Warning and Emergency Response system for your community',
        icon: Icons.shield_outlined,
        gradientColors: [
          Color(0xFFE53935), // Bright red from logo
          Color(0xFFB71C1C), // Darker red
          Color(0xFF5D5D5D), // Dark gray from logo
        ],
      ),

      // Page 2: Features - Gray to Red gradient
      const OnboardingPage(
        title: 'Monitor Hazards in Real-Time',
        description:
            'Report emergencies, track hazards, and keep your community safe',
        icon: Icons.warning_amber_rounded,
        gradientColors: [
          Color(0xFF5D5D5D), // Dark gray from logo
          Color(0xFF9E9E9E), // Medium gray
          Color(0xFFE53935), // Bright red from logo
        ],
      ),

      // Page 3: Get Started - Red accent gradient
      const OnboardingPage(
        title: 'Join the Network',
        description:
            'Create an account and start protecting your community today',
        icon: Icons.people_outline,
        gradientColors: [
          Color(0xFFB71C1C), // Dark red
          Color(0xFFE53935), // Bright red from logo
          Color(0xFFFF5252), // Lighter red accent
        ],
      ),
    ];
  }
}
