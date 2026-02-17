import 'dart:convert';
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:appwrite/appwrite.dart';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// Service for sending emails via Resend through Appwrite Cloud Functions
///
/// This service provides methods to send various types of transactional emails
/// including password resets, verification codes, and hazard alerts.
///
/// **Important**: Emails are sent through Appwrite Cloud Functions, not directly
/// from the app, to keep API keys secure.
class EmailService {
  // Singleton pattern
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  /// Send password reset email with reset link
  ///
  /// [email] - Recipient email address
  /// [resetLink] - Password reset URL with token
  ///
  /// Returns true if email was sent successfully
  Future<bool> sendPasswordReset(String email, String resetLink) async {
    return await _sendEmail(
      type: 'passwordReset',
      to: email,
      data: {'resetLink': resetLink},
    );
  }

  /// Send email verification code
  ///
  /// [email] - Recipient email address
  /// [code] - 6-digit verification code
  ///
  /// Returns true if email was sent successfully
  Future<bool> sendVerificationCode(
    String email,
    String code, {
    String? name,
  }) async {
    return await _sendEmail(
      type: 'verification',
      to: email,
      data: {'code': code, 'name': name},
    );
  }

  /// Send welcome email to new users
  ///
  /// [email] - User's email address
  /// [name] - User's name
  ///
  /// Returns true if email was sent successfully
  Future<bool> sendWelcomeEmail(String email, String name) async {
    return await _sendEmail(type: 'welcome', to: email, data: {'name': name});
  }

  /// Send hazard alert notification via email
  ///
  /// [email] - Recipient email address
  /// [hazardType] - Type of hazard (e.g., 'Flood', 'Drought')
  /// [severity] - Alert severity ('Low', 'Medium', 'High', 'Critical')
  /// [location] - Affected location
  /// [description] - Detailed alert description
  ///
  /// Returns true if email was sent successfully
  Future<bool> sendHazardAlert({
    required String email,
    required String hazardType,
    required String severity,
    required String location,
    required String description,
  }) async {
    return await _sendEmail(
      type: 'hazardAlert',
      to: email,
      data: {
        'hazardType': hazardType,
        'severity': severity,
        'location': location,
        'description': description,
      },
    );
  }

  /// Send report status update email
  ///
  /// [email] - User's email address
  /// [reportId] - Report ID
  /// [status] - New report status
  /// [message] - Status update message
  ///
  /// Returns true if email was sent successfully
  Future<bool> sendReportStatusUpdate({
    required String email,
    required String reportId,
    required String status,
    required String message,
  }) async {
    return await _sendEmail(
      type: 'reportUpdate',
      to: email,
      data: {'reportId': reportId, 'status': status, 'message': message},
    );
  }

  /// Generic email sender - calls Appwrite Cloud Function
  ///
  /// [type] - Email template type
  /// [to] - Recipient email address
  /// [data] - Template data (varies by type)
  ///
  /// Returns true if email was sent successfully
  Future<bool> _sendEmail({
    required String type,
    required String to,
    required Map<String, dynamic> data,
  }) async {
    try {
      // Validate email format
      if (!_isValidEmail(to)) {
        debugPrint('Invalid email address: $to');
        return false;
      }

      // Validate function configuration
      const functionId = 'alert-distribution';
      debugPrint('Executing Appwrite Function: $functionId');

      if (functionId.isEmpty) {
        throw Exception('Appwrite Function ID is empty. Check configuration.');
      }

      // Call Appwrite Cloud Function
      final functions = Functions(AppwriteService().appwriteClient);
      final response = await functions.createExecution(
        functionId: functionId,
        body: jsonEncode({
          'type':
              'direct-email', // Required to trigger email mode in alert-distribution
          'template': type, // Maps to 'template' in func
          'to': to,
          'data': data,
        }),
      );

      // Parse response
      final result = jsonDecode(response.responseBody);
      final success = result['success'] == true;

      if (success) {
        debugPrint('Email sent successfully: $type to $to');
      } else {
        final errorMsg = result['error'] ?? 'Unknown error';
        debugPrint('Email send failed: $errorMsg');

        // Show error to user to help debugging (especially for API key issues)
        Fluttertoast.showToast(
          msg: 'Email Error: $errorMsg',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }

      return success;
    } on AppwriteException catch (e) {
      debugPrint('Appwrite function error: ${e.message}');
      Fluttertoast.showToast(
        msg: 'System Error: ${e.message}',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
      return false;
    } on Exception catch (e) {
      debugPrint('Email service error: $e');
      return false;
    }
  }

  /// Validate email address format
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }
}
