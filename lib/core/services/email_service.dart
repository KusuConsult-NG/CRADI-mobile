import 'dart:developer' as developer;
import 'dart:convert';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;

/// Service for sending transactional emails.
///
/// Emails are sent by the Railway backend (`POST ${BACKEND_URL}/email`); the
/// email provider API key lives only on the server. Every request carries the
/// signed-in user's Supabase access token. The backend only allows sending to
/// the caller's own address unless the caller is approved staff/admin.
///
/// Account verification and password-recovery codes are sent by Supabase Auth
/// itself and do not go through this service.
class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  static Uri get _endpoint => Uri.parse('${AppConfig.backendUrl}/email');

  // ── Public send methods ────────────────────────────────────────────────────

  /// [resetLink] must be an https URL (rejected by the backend otherwise).
  Future<bool> sendPasswordReset(String email, String resetLink) =>
      _send(type: 'passwordReset', to: email, data: {'resetLink': resetLink});

  Future<bool> sendWelcomeEmail(String email, String name) =>
      _send(type: 'welcome', to: email, data: {'name': name, 'email': email});

  Future<bool> sendHazardAlert({
    required String email,
    required String hazardType,
    required String severity,
    required String location,
    required String description,
  }) => _send(
    type: 'hazardAlert',
    to: email,
    data: {
      'hazardType': hazardType,
      'severity': severity,
      'location': location,
      'description': description,
    },
  );

  Future<bool> sendReportStatusUpdate({
    required String email,
    required String reportId,
    required String status,
    required String message,
  }) => _send(
    type: 'reportUpdate',
    to: email,
    data: {'reportId': reportId, 'status': status, 'message': message},
  );

  // ── Core sender ────────────────────────────────────────────────────────────

  Future<bool> _send({
    required String type,
    required String to,
    required Map<String, dynamic> data,
  }) async {
    if (!_isValidEmail(to)) {
      developer.log('[EmailService] Invalid email: $to', name: 'EmailService');
      return false;
    }

    if (AppConfig.backendUrl.isEmpty) {
      developer.log(
        '[EmailService] BACKEND_URL not configured; cannot send "$type"',
        name: 'EmailService',
      );
      return false;
    }

    try {
      final token = SupabaseService().accessToken;
      if (token == null || token.isEmpty) {
        developer.log(
          '[EmailService] Not signed in; cannot send "$type" email',
          name: 'EmailService',
        );
        _showErrorToast();
        return false;
      }
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      final response = await http.post(
        _endpoint,
        headers: headers,
        body: jsonEncode({'type': type, 'to': to, 'data': data}),
      );

      final success = response.statusCode >= 200 && response.statusCode < 300;
      developer.log(
        '[EmailService] type=$type to=$to status=${response.statusCode} '
        'success=$success',
        name: 'EmailService',
      );

      if (!success) {
        developer.log(
          '[EmailService] Backend error body: ${response.body}',
          name: 'EmailService',
        );
        _showErrorToast();
      }
      return success;
    } on Exception catch (e) {
      developer.log('[EmailService] Exception: $e', name: 'EmailService');
      _showErrorToast();
      return false;
    }
  }

  void _showErrorToast() {
    Fluttertoast.showToast(
      msg: 'Email could not be sent. Please try again.',
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: Colors.red,
      textColor: Colors.white,
    );
  }

  bool _isValidEmail(String email) => RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  ).hasMatch(email);
}
