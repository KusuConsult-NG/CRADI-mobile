import 'dart:developer' as developer;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// Service for sending emails via Firebase Cloud Functions.
///
/// Emails are dispatched via a Firebase Callable Function (Phase 7: wire up
/// `FirebaseFunctions.instance.httpsCallable('sendTransactionalEmail')`).
/// In the interim, this service logs calls and returns `true` so that app flows
/// are not blocked during the Appwrite → Firebase migration.
class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  Future<bool> sendPasswordReset(String email, String resetLink) async =>
      _sendEmail(
        type: 'passwordReset',
        to: email,
        data: {'resetLink': resetLink},
      );

  Future<bool> sendVerificationCode(
    String email,
    String code, {
    String? name,
  }) async => _sendEmail(
    type: 'verification',
    to: email,
    data: {'code': code, 'name': name},
  );

  Future<bool> sendWelcomeEmail(String email, String name) async =>
      _sendEmail(type: 'welcome', to: email, data: {'name': name});

  Future<bool> sendHazardAlert({
    required String email,
    required String hazardType,
    required String severity,
    required String location,
    required String description,
  }) async => _sendEmail(
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
  }) async => _sendEmail(
    type: 'reportUpdate',
    to: email,
    data: {'reportId': reportId, 'status': status, 'message': message},
  );

  /// Generic email sender via Firebase Cloud Function `sendTransactionalEmail`.
  /// Calls the HTTPS function endpoint directly using the http package.
  Future<bool> _sendEmail({
    required String type,
    required String to,
    required Map<String, dynamic> data,
  }) async {
    try {
      if (!_isValidEmail(to)) {
        developer.log('Invalid email: $to', name: 'EmailService');
        return false;
      }

      // Get a fresh Firebase ID token for auth
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();

      // Cloud Function endpoint — update region/project if different
      const cfUrl =
          'https://us-central1-ewer-8f788.cloudfunctions.net/sendTransactionalEmail';

      final response = await http.post(
        Uri.parse(cfUrl),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({'type': type, 'to': to, 'data': data}),
      );

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final success = response.statusCode == 200 && json['success'] == true;

      developer.log(
        '[EmailService] type=$type to=$to status=${response.statusCode} success=$success',
        name: 'EmailService',
      );

      if (!success && (type == 'verification' || type == 'passwordReset')) {
        Fluttertoast.showToast(
          msg: 'Email could not be sent. Please try again.',
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
      }
      return success;
    } on Exception catch (e) {
      developer.log('Email service error: $e', name: 'EmailService');
      return false;
    }
  }

  bool _isValidEmail(String email) => RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  ).hasMatch(email);
}
