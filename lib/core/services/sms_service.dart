import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:climate_app/core/config/sms_config.dart';

/// SMS Service using Africa's Talking API
///
/// Handles sending SMS for alerts, notifications, and OTPs
///
/// Features:
/// - Send single SMS
/// - Send bulk SMS
/// - Delivery reports
/// - Error handling
/// - Sandbox/Production modes

class SmsService {
  // Singleton pattern
  static final SmsService _instance = SmsService._internal();
  factory SmsService() => _instance;
  SmsService._internal();

  // ==================== PUBLIC API ====================

  /// Send SMS to a single recipient
  ///
  /// [to]: Phone number in international format (e.g., +234XXXXXXXXXX or 234XXXXXXXXXX for Termii)
  /// [message]: SMS content
  /// [senderId]: Optional sender ID (defaults to config)
  ///
  /// Returns: MessageId if successful, null if failed
  Future<String?> sendSms({
    required String to,
    required String message,
    String? senderId,
    bool isDnd = false,
  }) async {
    try {
      // Validate configuration
      if (!SmsConfig.isConfigured) {
        developer.log(
          '❌ SMS not configured. Please update SmsConfig.',
          name: 'SmsService',
        );
        return null;
      }

      // Convert phone number to Termii expected format (no +)
      final formattedTo = _formatForTermii(to);

      // Validate phone number loosely because Termii takes numbers without '+' or space
      if (formattedTo.isEmpty) {
        developer.log('❌ Invalid phone number: $to', name: 'SmsService');
        return null;
      }

      // Prepare request
      final body = {
        'to': formattedTo,
        'from': senderId ?? SmsConfig.senderId,
        'sms': message,
        'type': 'plain',
        'channel': isDnd ? 'dnd' : 'generic', // "dnd" for OTPs if registered
        'api_key': SmsConfig.apiKey,
      };

      developer.log(
        '📤 Sending SMS to $formattedTo: ${message.substring(0, message.length > 50 ? 50 : message.length)}...',
        name: 'SmsService',
      );

      // Send request
      final response = await http
          .post(
            Uri.parse(SmsConfig.smsEndpoint),
            headers: SmsConfig.headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 15));

      // Handle response
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        final messageId = data['message_id'] as String?;
        // Termii ok response usually returns "ok" as code or 200
        if (messageId != null && messageId.isNotEmpty) {
          developer.log(
            '✅ SMS sent successfully. MessageId: $messageId',
            name: 'SmsService',
          );
          return messageId;
        }
      }

      developer.log(
        '❌ SMS API error: ${response.statusCode} - ${response.body}',
        name: 'SmsService',
      );
      return null;
    } on Exception catch (e) {
      developer.log('❌ SMS sending error: $e', name: 'SmsService');
      return null;
    }
  }

  /// Send SMS to multiple recipients (bulk SMS)
  ///
  /// [recipients]: List of phone numbers in international format
  /// [message]: SMS content
  /// [senderId]: Optional sender ID
  ///
  /// Returns: Map of phone numbers to message IDs
  Future<Map<String, String?>> sendBulkSms({
    required List<String> recipients,
    required String message,
    String? senderId,
  }) async {
    try {
      // Validate configuration
      if (!SmsConfig.isConfigured) {
        developer.log(
          '❌ SMS not configured. Please update SmsConfig.',
          name: 'SmsService',
        );
        return {};
      }

      // Filter and format valid phone numbers for Termii
      final validRecipients = recipients
          .map((e) => _formatForTermii(e))
          .where((e) => e.isNotEmpty)
          .toList();

      if (validRecipients.isEmpty) {
        developer.log(
          '❌ No valid phone numbers in bulk SMS',
          name: 'SmsService',
        );
        return {};
      }

      // Termii expects multiple numbers as an array of strings in to[] or just an array
      final body = {
        'to': validRecipients,
        'from': senderId ?? SmsConfig.senderId,
        'sms': message,
        'type': 'plain',
        'channel': 'generic',
        'api_key': SmsConfig.apiKey,
      };

      developer.log(
        '📤 Sending bulk SMS to ${validRecipients.length} recipients',
        name: 'SmsService',
      );

      // Send request
      final response = await http
          .post(
            Uri.parse(SmsConfig.bulkSmsEndpoint),
            headers: SmsConfig.headers,
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 15));

      // Handle response
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        // Termii bulk API typically returns a message_id and an array of unsuccessful contacts if any
        final results = <String, String?>{};
        final messageId = data['message_id']?.toString() ?? 'bulk_sent';

        developer.log(
          '✅ Bulk SMS sent successfully. MessageId: $messageId',
          name: 'SmsService',
        );

        for (final number in validRecipients) {
          results[number] = messageId;
        }

        return results;
      }

      developer.log(
        '❌ Bulk SMS API error: ${response.statusCode} - ${response.body}',
        name: 'SmsService',
      );
      return {};
    } on Exception catch (e) {
      developer.log('❌ Bulk SMS error: $e', name: 'SmsService');
      return {};
    }
  }

  /// Send alert SMS to authorities
  ///
  /// [alertTitle]: Title of the alert
  /// [location]: Location of the incident
  /// [severity]: Severity level
  /// [authorityContacts]: List of authority phone numbers
  ///
  /// Returns: Number of successful sends
  Future<int> sendAlertToAuthorities({
    required String alertTitle,
    required String location,
    required String severity,
    required List<String> authorityContacts,
  }) async {
    final message =
        '''
🚨 EWER ALERT
Severity: ${severity.toUpperCase()}
Type: $alertTitle
Location: $location
Respond immediately.
''';

    final results = await sendBulkSms(
      recipients: authorityContacts,
      message: message,
    );

    return results.values.where((id) => id != null).length;
  }

  /// Send alert SMS to affected community members
  ///
  /// [alertTitle]: Title of the alert
  /// [location]: Location of the incident
  /// [safetyInstructions]: Safety instructions
  /// [userContacts]: List of user phone numbers
  ///
  /// Returns: Number of successful sends
  Future<int> sendAlertToUsers({
    required String alertTitle,
    required String location,
    required String safetyInstructions,
    required List<String> userContacts,
  }) async {
    final message =
        '''
⚠️ CLIMATE ALERT
$alertTitle in $location
Safety: $safetyInstructions
Stay safe. For updates, check EWER app.
''';

    final results = await sendBulkSms(
      recipients: userContacts,
      message: message,
    );

    return results.values.where((id) => id != null).length;
  }

  /// Send OTP for verification
  ///
  /// [to]: Phone number
  /// [otp]: OTP code
  ///
  /// Returns: MessageId if successful
  Future<String?> sendOtp({required String to, required String otp}) async {
    final message =
        '''
Your EWER verification code is: $otp
Valid for 10 minutes.
Do not share this code.
''';

    return await sendSms(to: to, message: message, isDnd: true);
  }

  // ==================== HELPER METHODS ====================

  /// Format phone number for Termii
  /// Accepts: +234XXXXXXXXXX, 234XXXXXXXXXX, 080XXXXXXXX, etc.
  /// Converts to: 234XXXXXXXXXX (No + symbol)
  String _formatForTermii(String phone) {
    // Remove whitespace and special characters
    var cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');

    // If starts with 0 for Nigerian numbers, prepend 234
    if (cleaned.startsWith('0')) {
      return '234${cleaned.substring(1)}';
    }

    return cleaned;
  }

  /// Format phone number to international format
  /// Converts: 0803XXXXXXX → +2348XXXXXXXX (for Nigeria)
  String formatPhoneNumber(String phone, {String countryCode = '+234'}) {
    // Remove whitespace and special characters
    var cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // Already in international format
    if (cleaned.startsWith('+')) {
      return cleaned;
    }

    // Remove leading zero
    if (cleaned.startsWith('0')) {
      cleaned = cleaned.substring(1);
    }

    // Add country code
    return '$countryCode$cleaned';
  }

  /// Get configuration status
  String getConfigurationStatus() {
    return SmsConfig.configurationStatus;
  }

  /// Check if SMS service is ready
  bool get isReady => SmsConfig.isConfigured;

  /// Check if running in sandbox mode
  bool get isSandbox => SmsConfig.isSandbox;
}
