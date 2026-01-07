import 'package:climate_app/core/providers/settings_provider.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _slides = [
    {
      'title': 'Early Warning System',
      'description':
          'Receive real-time alerts about climate hazards in your area. Stay ahead of potential disasters.',
      'icon': Icons.notifications_active_outlined,
      'color': AppColors.primaryRed,
    },
    {
      'title': 'Report Hazards',
      'description':
          'Help your community by identifying and reporting climate hazards. Your reports can save lives.',
      'icon': Icons.report_problem_outlined,
      'color': Colors.orange,
    },
    {
      'title': 'Community Resilience',
      'description':
          'Access knowledge guides and connect with emergency services when you need them most.',
      'icon': Icons.people_outline,
      'color': Colors.blue,
    },
  ];

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
  }

  Future<void> _finishOnboarding() async {
    // Mark onboarding as seen in SettingsProvider
    final settings = context.read<SettingsProvider>();
    await settings.setOnboardingSeen(true);

    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finishOnboarding,
                child: Text(
                  'Skip',
                  style: GoogleFonts.lexend(
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: (slide['color'] as Color).withValues(
                              alpha: 0.1,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            slide['icon'] as IconData,
                            size: 80,
                            color: slide['color'] as Color,
                          ),
                        ),
                        const SizedBox(height: 48),
                        Text(
                          slide['title'] as String,
                          style: GoogleFonts.outfit(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          slide['description'] as String,
                          style: GoogleFonts.lexend(
                            fontSize: 16,
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? AppColors.primaryRed
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  CustomButton(
                    text: _currentPage == _slides.length - 1
                        ? 'Get Started'
                        : 'Next',
                    onPressed: () {
                      if (_currentPage == _slides.length - 1) {
                        _finishOnboarding();
                      } else {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
