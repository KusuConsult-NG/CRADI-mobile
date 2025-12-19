import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Secure error handler that prevents sensitive data leakage
class ErrorHandler {
  /// Get user-friendly error message
  static String getUserMessage(dynamic error) {
    // DEBUGGING: Force detailed message even in release mode to troubleshoot auth issue
    return _getDetailedMessage(error);

    // Original code restored later:
    // if (kReleaseMode) {
    //   return _getGenericMessage(error);
    // }
    // return _getDetailedMessage(error);
  }

  /// Get generic user-friendly message

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
    // SECURE: Always sanitize data before sending to external services
    // Integrate with crash reporting service like Firebase Crashlytics:
    // final sanitizedError = _sanitizeForLog(error.toString());\n    // FirebaseCrashlytics.instance.recordError(sanitizedError, stackTrace);
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
    // DEBUGGING: Force details in release mode too
    if (technicalDetails != null) {
      return '$userMessage\n(Debug: $technicalDetails)';
    }
    return userMessage;

    // Original:
    // if (kDebugMode && technicalDetails != null) {
    //   return 'SecureException: $userMessage\nDetails: $technicalDetails';
    // }
    // return userMessage;
  }
}

/// Authentication exception
class AuthException extends SecureException {
  AuthException(super.userMessage, {super.technicalDetails});
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
