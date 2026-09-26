import 'dart:convert';

/// Application configuration constants
///
/// This file contains configuration flags and constants that can be
/// modified for development, testing, and production environments.
class AppConfig {
  AppConfig._();

  // ─────────────────────── Firestore collection names ──────────────────────

  static const String usersCollection = 'users';
  static const String reportsCollection = 'reports';
  static const String verificationsCollection = 'verifications';
  static const String alertsCollection = 'alerts';
  static const String chatsCollection = 'chats';
  static const String messagesCollection = 'messages';
  static const String contactsCollection = 'contacts';
  static const String knowledgeBaseCollection = 'knowledge_base';
  static const String trustedDevicesCollection = 'trusted_devices';
  static const String loginHistoryCollection = 'login_history';
  static const String scheduledEscalationsCollection = 'scheduled_escalations';
  static const String verificationsOverrideCollection =
      'verification_overrides';
  static const String authoritiesCollection = 'authorities';

  // ─────────────────────── Firebase Storage paths ──────────────────────────

  static const String profileImagesBucket = 'profile_images';
  static const String reportImagesBucket = 'report_images';

  // ─────────────────────── Feature flags ───────────────────────────────────

  /// Enable development bypass for OTP verification.
  /// IMPORTANT: Must be false in production!
  static const bool enableOtpBypass = false;

  /// Development bypass OTP code.
  static const String devBypassOtp = '1111';

  /// Enable verbose logging (automatically disabled in release builds).
  static const bool verboseLogging =
      bool.fromEnvironment('dart.vm.product') == false;

  // ─────────────────────── App constants ───────────────────────────────────

  /// Session timeout in minutes.
  static const int sessionTimeoutMinutes = 30;

  /// Maximum login attempts before account lock.
  static const int maxLoginAttempts = 5;

  // ─────────────────────── Alert validation ────────────────────────────────

  /// Minimum peer confirmations before auto-validating a report.
  /// 2 prevents a single actor from triggering a system-wide alert alone.
  static const int minimumPeerConfirmations = 2;

  // ─────────────────────── Branding ────────────────────────────────────────

  static const String appName = 'EWER';
  static const String appFullName = 'Early Warning and Emergency Response';
  static const String appTagline = 'Early Warning & Emergency Response';
  static const String appVersion = '1.0.5+8';

  // ─────────────────────── Supabase Backend ────────────────────────────────
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://splfkqazwzybityoqmyv.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNwbGZrcWF6d3p5Yml0eW9xbXl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAzNjg5MzcsImV4cCI6MjEwNTk0NDkzN30.B3p-MTWYacngdF0uGCxDXZNqL7gxYMQNfKp_6i-7QfQ',
  );

  // ─────────────────────── OneSignal Push Notifications ────────────────────
  static const String oneSignalAppId = String.fromEnvironment(
    'ONESIGNAL_APP_ID',
    defaultValue: '2e6f30a8-ef18-4091-9961-e6a6fe862322',
  );
  static String get oneSignalRestKey {
    const envKey = String.fromEnvironment('ONESIGNAL_REST_KEY');
    if (envKey.isNotEmpty) return envKey;
    const envApiKey = String.fromEnvironment('ONESIGNAL_REST_API_KEY');
    if (envApiKey.isNotEmpty) return envApiKey;
    return utf8.decode(base64.decode(
      'b3NfdjJfYXBwX2Z6eHRia2hwZGJhamRnbGI0MnRwNWJyZGVrZXZzc210dWZ2ZWFqZTNhejV5YWRyaTJtcHQyejJpcmR3YmY2b215dW1qbGJ3cWU2dzY2c2syN3YyNnlyeG5weHV6Y2lxZ3diczY3b2E=',
    ));
  }
}
