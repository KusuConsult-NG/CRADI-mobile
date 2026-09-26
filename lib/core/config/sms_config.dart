/// Termii SMS Configuration
///
/// Store credentials securely — never commit API keys to version control.
///
/// Required build-time inject:
///   flutter run  --dart-define=TERMII_API_KEY=re_xxxx
///   flutter build apk --dart-define=TERMII_API_KEY=re_xxxx
///
/// Or via file:
///   flutter run --dart-define-from-file=.env.dart-define
library;

class SmsConfig {
  // ==================== CONFIGURATION ====================

  /// Termii API Key — injected at build time via --dart-define=TERMII_API_KEY=xxx
  /// Defaults to empty string; app will not send SMS if missing.
  static const String apiKey = String.fromEnvironment(
    'TERMII_API_KEY',
    defaultValue: '',
  );

  /// Sender ID — CRADI is active; EWER is pending NCC approval (submitted 22 Feb 2026).
  /// Switch back to 'EWER' once approved at https://app.termii.com/dashboard/sender-id
  static const String senderId = String.fromEnvironment(
    'TERMII_SENDER_ID',
    defaultValue: 'CRADI',
  );

  /// API Base URL
  static const String baseUrl = 'https://api.ng.termii.com';

  /// Set to false for production
  static const bool isSandbox = false;

  // ==================== COMPUTED VALUES ====================

  /// SMS Endpoint
  static String get smsEndpoint => '$baseUrl/api/sms/send';

  /// Bulk SMS Endpoint
  static String get bulkSmsEndpoint => '$baseUrl/api/sms/send/bulk';

  /// Headers for API requests
  static Map<String, String> get headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  // ==================== SETUP INSTRUCTIONS ====================

  /// Setup Steps:
  /// 1. Sign up at https://termii.com
  /// 2. Get your API key from the dashboard settings
  /// 3. For production:
  ///    - Register your sender ID
  ///    - Add funds to your account
  /// 4. Provide API key via --dart-define=TERMII_API_KEY=...

  // ==================== VALIDATION ====================

  /// Check if configuration is valid
  static bool get isConfigured {
    return apiKey != 'YOUR_API_KEY_HERE' && apiKey.isNotEmpty;
  }

  /// Get configuration status message
  static String get configurationStatus {
    if (!isConfigured) {
      return 'SMS Configuration incomplete. Please update SmsConfig with your Termii credentials.';
    }
    if (isSandbox) {
      return 'SMS Service configured for TESTING (ensure test sender ID is used).';
    }
    return 'SMS Service configured for PRODUCTION.';
  }
}
