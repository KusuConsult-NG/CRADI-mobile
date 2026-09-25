import 'dart:developer' as developer;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;

/// Service for sending transactional emails.
///
/// Emails are sent through the `sendTransactionalEmail` Cloud Function
/// (see `firebase-functions/index.js`). The email provider API key lives only
/// on the server; the client never holds it. Templates are rendered
/// server-side from `firebase-functions/email_templates.js`.
///
/// Requests carry the current user's Firebase ID token. The only request
/// allowed without a token is a `verification` email during registration.
class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  static const String _functionUrl =
      'https://us-central1-ewer-8f788.cloudfunctions.net/sendTransactionalEmail';

  // ── Public send methods ────────────────────────────────────────────────────

  Future<bool> sendVerificationCode(
    String email,
    String code, {
    String? name,
  }) => _send(
    type: 'verification',
    to: email,
    data: {'code': code, 'name': name ?? 'User'},
  );

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

    try {
      final headers = <String, String>{'Content-Type': 'application/json'};

      final user = FirebaseAuth.instance.currentUser;
      final idToken = await user?.getIdToken();
      if (idToken != null && idToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $idToken';
      } else if (type != 'verification') {
        // The Cloud Function rejects unauthenticated requests for every
        // type except the registration OTP.
        developer.log(
          '[EmailService] Not signed in; cannot send "$type" email',
          name: 'EmailService',
        );
        _showErrorToast();
        return false;
      }

      final response = await http.post(
        Uri.parse(_functionUrl),
        headers: headers,
        body: jsonEncode({'type': type, 'to': to, 'data': data}),
      );

      final success = response.statusCode == 200;
      developer.log(
        '[EmailService] type=$type to=$to status=${response.statusCode} '
        'success=$success',
        name: 'EmailService',
      );

      if (!success) {
        developer.log(
          '[EmailService] Function error body: ${response.body}',
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
