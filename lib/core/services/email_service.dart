import 'dart:developer' as developer;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;

/// Service for sending transactional emails via Resend (https://resend.com).
///
/// The Resend API key is injected at build time:
///   flutter run  --dart-define=RESEND_API_KEY=re_xxxx
///   flutter build apk --dart-define=RESEND_API_KEY=re_xxxx
///
/// You can also add it to your IDE launch config or VS Code launch.json:
///   "args": ["--dart-define=RESEND_API_KEY=re_xxxx"]
///
/// To avoid re-typing the key every run, create `.env.dart-define` at the
/// project root with:
///   RESEND_API_KEY=re_xxxx
/// then run:
///   flutter run --dart-define-from-file=.env.dart-define
class EmailService {
  static final EmailService _instance = EmailService._internal();
  factory EmailService() => _instance;
  EmailService._internal();

  // Hardcoded to guarantee functionality regardless of IDE launch args
  static const String _apiKey = 're_C1GhEJ5U_DScqhvDStZ21HTfCo5HisWUe';

  static const String _resendUrl = 'https://api.resend.com/emails';

  // Sender identity — update FROM_EMAIL to your verified Resend domain.
  static const String _fromEmail = 'apps@ewer.cradil.org';
  static const String _fromName = 'EWER Alert System';

  // ── Public send methods ────────────────────────────────────────────────────

  Future<bool> sendVerificationCode(
    String email,
    String code, {
    String? name,
  }) => _send(
    to: email,
    subject: 'Your CRADI Verification Code: $code',
    html: _verificationHtml(code: code, name: name ?? 'User'),
  );

  Future<bool> sendPasswordReset(String email, String resetLink) => _send(
    to: email,
    subject: 'Reset Your CRADI Password',
    html: _passwordResetHtml(resetLink: resetLink),
  );

  Future<bool> sendWelcomeEmail(String email, String name) => _send(
    to: email,
    subject: 'Welcome to CRADI Mobile - Early Warning System',
    html: _welcomeHtml(name: name, email: email),
  );

  Future<bool> sendHazardAlert({
    required String email,
    required String hazardType,
    required String severity,
    required String location,
    required String description,
  }) => _send(
    to: email,
    subject: '🚨 ${severity.toUpperCase()} Alert: $hazardType in $location',
    html: _hazardAlertHtml(
      hazardType: hazardType,
      severity: severity,
      location: location,
      description: description,
    ),
  );

  Future<bool> sendReportStatusUpdate({
    required String email,
    required String reportId,
    required String status,
    required String message,
  }) => _send(
    to: email,
    subject: 'Report Update: $status – Report #$reportId',
    html: _reportUpdateHtml(
      reportId: reportId,
      status: status,
      message: message,
    ),
  );

  // ── Core sender ────────────────────────────────────────────────────────────

  Future<bool> _send({
    required String to,
    required String subject,
    required String html,
  }) async {
    // Guard: API key must be present
    if (_apiKey.isEmpty) {
      developer.log(
        '[EmailService] ❌ RESEND_API_KEY not set. '
        'Build with --dart-define=RESEND_API_KEY=re_xxx',
        name: 'EmailService',
      );
      _showErrorToast();
      return false;
    }

    if (!_isValidEmail(to)) {
      developer.log('[EmailService] Invalid email: $to', name: 'EmailService');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(_resendUrl),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'from': '$_fromName <$_fromEmail>',
          'to': [to],
          'subject': subject,
          'html': html,
        }),
      );

      final success = response.statusCode == 200 || response.statusCode == 201;
      developer.log(
        '[EmailService] to=$to status=${response.statusCode} success=$success',
        name: 'EmailService',
      );

      if (!success) {
        developer.log(
          '[EmailService] Resend error body: ${response.body}',
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

  // ── Email Templates (inline HTML) ─────────────────────────────────────────

  static const String _brandRed = '#C62828';
  static const String _brandDarkRed = '#B71C1C';

  String _shell(String bodyContent) =>
      '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin:0; padding:20px; font-family:Arial,sans-serif; background-color:#f5f5f5;">
  <div style="max-width:600px; margin:0 auto; background-color:white; border-radius:8px; overflow:hidden;">
    $bodyContent
    <div style="background-color:#f9f9f9; padding:20px 30px; text-align:center; border-top:1px solid #e0e0e0;">
      <p style="color:#999; font-size:12px; margin:0;">
        This is an automated message from CRADI Mobile. Please do not reply to this email.
      </p>
    </div>
  </div>
</body>
</html>''';

  String _verificationHtml({required String code, required String name}) =>
      _shell('''
    <div style="background:linear-gradient(135deg,$_brandRed 0%,$_brandDarkRed 100%); padding:30px; text-align:center;">
      <h1 style="color:white; margin:0; font-size:24px;">CRADI Mobile</h1>
      <p style="color:white; margin:5px 0 0 0; opacity:0.9;">Early Warning System</p>
    </div>
    <div style="padding:40px 30px;">
      <h2 style="color:#333; margin-top:0;">Verification Code</h2>
      <p style="color:#666; line-height:1.6;">Hello $name,</p>
      <p style="color:#666; line-height:1.6;">Your one-time verification code is:</p>
      <div style="background-color:#f5f5f5; border-left:4px solid $_brandRed; padding:20px; margin:30px 0; text-align:center;">
        <h1 style="color:$_brandRed; font-size:42px; margin:0; letter-spacing:8px; font-family:'Courier New',monospace;">$code</h1>
      </div>
      <p style="color:#999; font-size:14px; line-height:1.6;">
        This code expires in <strong>10 minutes</strong>. Do not share it with anyone.
      </p>
    </div>''');

  String _passwordResetHtml({required String resetLink}) => _shell('''
    <div style="background:linear-gradient(135deg,$_brandRed 0%,$_brandDarkRed 100%); padding:30px; text-align:center;">
      <h1 style="color:white; margin:0; font-size:24px;">Password Reset</h1>
      <p style="color:white; margin:5px 0 0 0; opacity:0.9;">CRADI Mobile</p>
    </div>
    <div style="padding:40px 30px;">
      <h2 style="color:#333; margin-top:0;">Reset Your Password</h2>
      <p style="color:#666; line-height:1.6;">
        We received a request to reset the password for your CRADI account.
        Click the button below to set a new password:
      </p>
      <div style="text-align:center; margin:30px 0;">
        <a href="$resetLink"
           style="background-color:$_brandRed; color:white; padding:14px 32px;
                  text-decoration:none; border-radius:6px; font-weight:bold;
                  font-size:16px; display:inline-block;">
          Reset Password
        </a>
      </div>
      <p style="color:#999; font-size:14px; line-height:1.6;">
        This link expires in <strong>1 hour</strong>. If you did not request a
        password reset, please ignore this email — your account is safe.
      </p>
    </div>''');

  String _welcomeHtml({required String name, required String email}) =>
      _shell('''
    <div style="background:linear-gradient(135deg,$_brandRed 0%,$_brandDarkRed 100%); padding:40px; text-align:center;">
      <h1 style="color:white; margin:0; font-size:28px;">Welcome to CRADI!</h1>
      <p style="color:white; margin:10px 0 0 0; opacity:0.9;">Climate Resilience &amp; Development Initiative</p>
    </div>
    <div style="padding:40px 30px;">
      <h2 style="color:#333; margin-top:0;">Hello $name! 👋</h2>
      <p style="color:#666; line-height:1.6;">
        Thank you for joining the CRADI Mobile Early Warning System.
        Your account has been successfully created.
      </p>
      <div style="background-color:#e3f2fd; padding:20px; border-radius:4px; margin:20px 0;">
        <p style="margin:0; color:#1976d2;"><strong>Email:</strong> $email</p>
      </div>
      <h3 style="color:#333;">What you can do:</h3>
      <ul style="color:#666; line-height:1.8;">
        <li>Report climate hazards in your area</li>
        <li>Track the status of your reports</li>
        <li>Receive real-time alerts about verified hazards</li>
        <li>Access the knowledge base and safety resources</li>
        <li>Connect with emergency authorities</li>
      </ul>
    </div>''');

  String _hazardAlertHtml({
    required String hazardType,
    required String severity,
    required String location,
    required String description,
  }) {
    final sevColor = severity == 'Critical'
        ? '#d32f2f'
        : severity == 'High'
        ? '#ff9800'
        : '#fbc02d';
    return _shell('''
    <div style="background-color:$_brandRed; padding:20px; text-align:center;">
      <h1 style="color:white; margin:0; font-size:28px;">⚠️ EMERGENCY ALERT</h1>
    </div>
    <div style="padding:30px;">
      <div style="background-color:#fff3e0; border-left:4px solid #ff9800; padding:15px; margin-bottom:20px;">
        <p style="margin:0; color:#e65100; font-weight:bold;">ACTION REQUIRED: Climate Hazard Detected</p>
      </div>
      <table style="width:100%; border-collapse:collapse;">
        <tr>
          <td style="padding:12px; border-bottom:1px solid #e0e0e0; color:#666; font-weight:bold; width:30%;">Hazard Type:</td>
          <td style="padding:12px; border-bottom:1px solid #e0e0e0; color:#333;">$hazardType</td>
        </tr>
        <tr>
          <td style="padding:12px; border-bottom:1px solid #e0e0e0; color:#666; font-weight:bold;">Severity:</td>
          <td style="padding:12px; border-bottom:1px solid #e0e0e0;">
            <span style="background-color:$sevColor; color:white; padding:4px 12px; border-radius:4px; font-weight:bold;">
              ${severity.toUpperCase()}
            </span>
          </td>
        </tr>
        <tr>
          <td style="padding:12px; border-bottom:1px solid #e0e0e0; color:#666; font-weight:bold;">Location:</td>
          <td style="padding:12px; border-bottom:1px solid #e0e0e0; color:#333;">$location</td>
        </tr>
      </table>
      <div style="margin-top:20px; padding:20px; background-color:#f5f5f5; border-radius:4px;">
        <h3 style="margin-top:0; color:#333;">Description:</h3>
        <p style="color:#666; line-height:1.6; margin:0;">$description</p>
      </div>
    </div>''');
  }

  String _reportUpdateHtml({
    required String reportId,
    required String status,
    required String message,
  }) {
    final statusColor = status == 'Verified'
        ? '#4caf50'
        : status == 'Approved'
        ? '#2196f3'
        : '#ff9800';
    return _shell('''
    <div style="background:linear-gradient(135deg,$_brandRed 0%,$_brandDarkRed 100%); padding:30px; text-align:center;">
      <h1 style="color:white; margin:0; font-size:24px;">Report Status Update</h1>
    </div>
    <div style="padding:30px;">
      <table style="width:100%; border-collapse:collapse; margin:20px 0;">
        <tr>
          <td style="padding:12px; border-bottom:1px solid #e0e0e0; color:#666; font-weight:bold;">Report ID:</td>
          <td style="padding:12px; border-bottom:1px solid #e0e0e0; color:#333; font-family:monospace;">$reportId</td>
        </tr>
        <tr>
          <td style="padding:12px; border-bottom:1px solid #e0e0e0; color:#666; font-weight:bold;">New Status:</td>
          <td style="padding:12px; border-bottom:1px solid #e0e0e0;">
            <span style="background-color:$statusColor; color:white; padding:4px 12px; border-radius:4px; font-weight:bold;">
              ${status.toUpperCase()}
            </span>
          </td>
        </tr>
      </table>
      <div style="padding:20px; background-color:#f5f5f5; border-radius:4px;">
        <h3 style="margin-top:0; color:#333;">Message:</h3>
        <p style="color:#666; line-height:1.6; margin:0;">$message</p>
      </div>
      <p style="color:#666; line-height:1.6; margin-top:20px;">
        Thank you for helping keep our communities safe through the CRADI Early Warning System.
      </p>
    </div>''');
  }
}
