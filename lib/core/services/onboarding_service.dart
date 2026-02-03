import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const String _onboardingKey = 'has_completed_onboarding';

  /// Check if user has completed onboarding
  Future<bool> hasCompletedOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_onboardingKey) ?? false;
    } on Exception catch (e) {
      // If there's an error reading preferences, assume not completed
      debugPrint('Error reading onboarding status: $e');
      return false;
    }
  }

  /// Mark onboarding as completed
  Future<void> setOnboardingCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardingKey, true);
    } on Exception catch (e) {
      // Silently fail - user will see onboarding again next time
      debugPrint('Error saving onboarding status: $e');
    }
  }

  /// Reset onboarding status (for testing)
  Future<void> resetOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_onboardingKey);
    } on Exception catch (e) {
      debugPrint('Error resetting onboarding status: $e');
    }
  }
}
