import 'package:firebase_analytics/firebase_analytics.dart';
import 'dart:developer' as developer;

/// Service for tracking analytics events throughout the app
///
/// Provides centralized analytics tracking to monitor user behavior,
/// feature usage, and app performance.
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  FirebaseAnalyticsObserver getAnalyticsObserver() {
    return FirebaseAnalyticsObserver(analytics: _analytics);
  }

  /// Track report submission
  Future<void> logReportSubmitted({
    required String hazardType,
    required String severity,
    String? location,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'report_submitted',
        parameters: {
          'hazard_type': hazardType,
          'severity': severity,
          if (location != null) 'location': location,
        },
      );
    } on Exception catch (e) {
      developer.log('Analytics error: $e', name: 'AnalyticsService');
    }
  }

  /// Track report verification
  Future<void> logReportVerified({
    required String reportId,
    required bool isApproved,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'report_verified',
        parameters: {'report_id': reportId, 'is_approved': isApproved},
      );
    } on Exception catch (e) {
      developer.log('Analytics error: $e', name: 'AnalyticsService');
    }
  }

  /// Track biometric auth usage
  Future<void> logBiometricAuth({required bool success}) async {
    try {
      await _analytics.logEvent(
        name: 'biometric_auth',
        parameters: {'success': success},
      );
    } on Exception catch (e) {
      developer.log('Analytics error: $e', name: 'AnalyticsService');
    }
  }

  /// Track screen views
  Future<void> logScreenView({required String screenName}) async {
    try {
      await _analytics.logScreenView(screenName: screenName);
    } on Exception catch (e) {
      developer.log('Analytics error: $e', name: 'AnalyticsService');
    }
  }

  /// Track user login
  Future<void> logLogin({required String method}) async {
    try {
      await _analytics.logLogin(loginMethod: method);
    } on Exception catch (e) {
      developer.log('Analytics error: $e', name: 'AnalyticsService');
    }
  }

  /// Track feature usage
  Future<void> logFeatureUsed({
    required String featureName,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'feature_used',
        parameters: {'feature_name': featureName, ...?parameters},
      );
    } on Exception catch (e) {
      developer.log('Analytics error: $e', name: 'AnalyticsService');
    }
  }
}
