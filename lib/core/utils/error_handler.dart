import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Secure error handler that prevents sensitive data leakage
class ErrorHandler {
  /// Get user-friendly error message
  static String getUserMessage(dynamic error) {
    if (kReleaseMode) {
      return _getGenericMessage(error);
    }
    return _getDetailedMessage(error);
  }

  /// Get generic user-friendly message (release builds).
  /// IMPORTANT: SDK-internal messages must NEVER be surfaced raw to the user —
  /// they leak implementation detail and confuse end users.
  static String _getGenericMessage(dynamic error) {
    if (error.runtimeType.toString() == 'AuthException') {
      return error.toString();
    }

    final msg = error.toString().toLowerCase();
    // Network / connectivity
    if (msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('connection')) {
      return 'Network error. Please check your connection.';
    }
    // Permission / access
    if (msg.contains('permission') || msg.contains('denied')) {
      return 'You do not have permission to perform this action.';
    }
    // SDK internal strings — must be scrubbed
    if (msg.contains('internal error') ||
        msg.contains('postgrest') ||
        msg.contains('authapiexception')) {
      return 'An error occurred. Please try again or contact support.';
    }
    return 'An unexpected error occurred. Please try again.';
  }

  /// Get detailed message (debug mode only)
  static String _getDetailedMessage(dynamic error) {
    if (error is Exception) {
      return 'Error: ${error.toString()}';
    }
    return 'Error: $error';
  }

  /// Log error securely (sanitized)
  static void logError(
    dynamic error, {
    StackTrace? stackTrace,
    String? context,
  }) {
    if (kDebugMode) {
      developer.log(
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
        name: 'ErrorHandler',
      );
      developer.log(
        '🔴 ERROR${context != null ? ' in $context' : ''}',
        name: 'ErrorHandler',
      );
      developer.log(
        'Error: ${_sanitizeForLog(error.toString())}',
        name: 'ErrorHandler',
      );
      if (stackTrace != null) {
        developer.log('Stack trace:', name: 'ErrorHandler');
        developer.log(_sanitizeStackTrace(stackTrace), name: 'ErrorHandler');
      }
      developer.log(
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
        name: 'ErrorHandler',
      );
    }

    // In production, send to analytics/crash reporting (sanitized)
    if (kReleaseMode) {
      _sendToAnalytics(error, stackTrace, context);
    }
  }

  /// Sanitize log output to remove sensitive data
  static String _sanitizeForLog(String log) {
    String sanitized = log;

    // Remove potential tokens
    sanitized = sanitized.replaceAll(
      RegExp(r'(token|auth|bearer)[\s:=]+[\w\-\.]+', caseSensitive: false),
      r'$1: [REDACTED]',
    );

    // Remove potential passwords
    sanitized = sanitized.replaceAll(
      RegExp(r'(password|pwd|secret)[\s:=]+[^\s]+', caseSensitive: false),
      r'$1: [REDACTED]',
    );

    // Remove potential API keys
    sanitized = sanitized.replaceAll(
      RegExp(r'(key|api_key)[\s:=]+[^\s]+', caseSensitive: false),
      r'$1: [REDACTED]',
    );

    // Remove phone numbers
    sanitized = sanitized.replaceAll(RegExp(r'\+?\d{10,15}'), '[PHONE]');

    // Remove email addresses
    sanitized = sanitized.replaceAll(
      RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'),
      '[EMAIL]',
    );

    return sanitized;
  }

  /// Sanitize stack trace
  static String _sanitizeStackTrace(StackTrace stackTrace) {
    return _sanitizeForLog(stackTrace.toString());
  }

  /// Send to analytics/crash reporting service
  static void _sendToAnalytics(
    dynamic error,
    StackTrace? stackTrace,
    String? context,
  ) {
    // SECURE: Always sanitize data before sending to external services.
    // No-op unless Sentry was initialised (SENTRY_DSN provided).
    if (!Sentry.isEnabled) return;
    final sanitizedError = _sanitizeForLog(error.toString());
    Sentry.captureMessage(
      context != null ? '[$context] $sanitizedError' : sanitizedError,
      level: SentryLevel.error,
    );
  }

  /// Handle and display error to user
  static String handleError(dynamic error, {String? context}) {
    logError(error, context: context);
    return getUserMessage(error);
  }
}

/// Custom secure exception
class SecureException implements Exception {
  final String userMessage;
  final String? technicalDetails;

  SecureException(this.userMessage, {this.technicalDetails});

  @override
  String toString() {
    if (kDebugMode && technicalDetails != null) {
      return 'SecureException: $userMessage\nDetails: $technicalDetails';
    }
    return userMessage;
  }
}

/// Authentication exception
class AuthException extends SecureException {
  AuthException(super.userMessage, {super.technicalDetails});
}

/// Sign-in refused because the email address has not been confirmed yet.
/// A fresh verification code has been sent to [email].
class EmailNotConfirmedException extends AuthException {
  EmailNotConfirmedException(this.email)
    : super('Please verify your email first. We sent a new code to $email.');
  final String email;
}

/// Network exception
class NetworkException extends SecureException {
  NetworkException(super.userMessage, {super.technicalDetails});
}

/// Validation exception
class ValidationException extends SecureException {
  ValidationException(super.userMessage, {super.technicalDetails});
}

/// Storage exception
class StorageException extends SecureException {
  StorageException(super.userMessage, {super.technicalDetails});
}
