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
  /// [to]: Phone number in international format (e.g., +234XXXXXXXXXX)
  /// [message]: SMS content (max 160 chars for single SMS, 918 for concatenated)
  /// [senderId]: Optional sender ID (defaults to config)
  ///
  /// Returns: MessageId if successful, null if failed
  Future<String?> sendSms({
    required String to,
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
        return null;
      }

      // Validate phone number
      if (!_isValidPhoneNumber(to)) {
        developer.log('❌ Invalid phone number: $to', name: 'SmsService');
        return null;
      }

      // Prepare request
      final body = {
        'username': SmsConfig.username,
        'to': to,
        'message': message,
        'from': senderId ?? SmsConfig.senderId,
      };

      developer.log(
        '📤 Sending SMS to $to: ${message.substring(0, message.length > 50 ? 50 : message.length)}...',
        name: 'SmsService',
      );

      // Send request
      final response = await http.post(
        Uri.parse(SmsConfig.smsEndpoint),
        headers: SmsConfig.headers,
        body: body,
      );

      // Handle response
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        // Africa's Talking response format
        final smsData = data['SMSMessageData'] as Map<String, dynamic>?;
        final recipients = smsData?['Recipients'] as List<dynamic>?;

        if (recipients != null && recipients.isNotEmpty) {
          final recipient = recipients[0] as Map<String, dynamic>;
          final status = recipient['status'] as String?;
          final messageId = recipient['messageId'] as String?;

          if (status == 'Success' || status == 'Sent') {
            developer.log(
              '✅ SMS sent successfully. MessageId: $messageId',
              name: 'SmsService',
            );
            return messageId;
          } else {
            developer.log(
              '❌ SMS failed to send. Status: $status',
              name: 'SmsService',
            );
            return null;
          }
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

      // Filter valid phone numbers
      final validRecipients = recipients.where(_isValidPhoneNumber).toList();

      if (validRecipients.isEmpty) {
        developer.log(
          '❌ No valid phone numbers in bulk SMS',
          name: 'SmsService',
        );
        return {};
      }

      // Prepare request (comma-separated phone numbers)
      final body = {
        'username': SmsConfig.username,
        'to': validRecipients.join(','),
        'message': message,
        'from': senderId ?? SmsConfig.senderId,
      };

      developer.log(
        '📤 Sending bulk SMS to ${validRecipients.length} recipients',
        name: 'SmsService',
      );

      // Send request
      final response = await http.post(
        Uri.parse(SmsConfig.smsEndpoint),
        headers: SmsConfig.headers,
        body: body,
      );

      // Handle response
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final smsData = data['SMSMessageData'] as Map<String, dynamic>?;
        final recipientsData = smsData?['Recipients'] as List<dynamic>?;

        final results = <String, String?>{};

        if (recipientsData != null) {
          for (final recipient in recipientsData) {
            final recipientMap = recipient as Map<String, dynamic>;
            final number = recipientMap['number'] as String?;
            final status = recipientMap['status'] as String?;
            final messageId = recipientMap['messageId'] as String?;

            if (number != null) {
              results[number] = (status == 'Success' || status == 'Sent')
                  ? messageId
                  : null;
            }
          }

          final successCount = results.values.where((id) => id != null).length;
          developer.log(
            '✅ Bulk SMS sent: $successCount/${validRecipients.length} successful',
            name: 'SmsService',
          );
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
🚨 CRADI ALERT
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
Stay safe. For updates, check CRADI app.
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
Your CRADI verification code is: $otp
Valid for 10 minutes.
Do not share this code.
''';

    return await sendSms(to: to, message: message, senderId: 'CRADI-OTP');
  }

  // ==================== HELPER METHODS ====================

  /// Validate phone number format
  /// Accepts: +234XXXXXXXXXX, +254XXXXXXXXX, etc.
  bool _isValidPhoneNumber(String phone) {
    // Remove whitespace
    final cleaned = phone.replaceAll(RegExp(r'\s+'), '');

    // Must start with + and have 10-15 digits
    final regex = RegExp(r'^\+[1-9]\d{9,14}$');
    return regex.hasMatch(cleaned);
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
