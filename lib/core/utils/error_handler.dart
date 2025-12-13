import 'package:flutter/foundation.dart';

/// Secure error handler that prevents sensitive data leakage
class ErrorHandler {
  /// Get user-friendly error message
  static String getUserMessage(dynamic error) {
    // In production, never expose technical details
    if (kReleaseMode) {
      return _getGenericMessage(error);
    }

    // In debug mode, can show more details
    return _getDetailedMessage(error);
  }

  /// Get generic user-friendly message
  static String _getGenericMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('connection')) {
      return 'Network error. Please check your internet connection and try again.';
    }

    if (errorString.contains('timeout')) {
      return 'Request timed out. Please try again.';
    }

    if (errorString.contains('auth') ||
        errorString.contains('unauthorized') ||
        errorString.contains('forbidden')) {
      return 'Authentication failed. Please login again.';
    }

    if (errorString.contains('not found') || errorString.contains('404')) {
      return 'Resource not found. Please try again later.';
    }

    if (errorString.contains('server') ||
        errorString.contains('500') ||
        errorString.contains('503')) {
      return 'Server error. Please try again later.';
    }

    if (errorString.contains('format') || errorString.contains('parse')) {
      return 'Invalid data format. Please try again.';
    }

    if (errorString.contains('storage') || errorString.contains('disk')) {
      return 'Storage error. Please check available space.';
    }

    if (errorString.contains('permission')) {
      return 'Permission denied. Please check app permissions.';
    }

    // Default generic message
    return 'An error occurred. Please try again.';
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
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔴 ERROR${context != null ? ' in $context' : ''}');
      print('Error: ${_sanitizeForLog(error.toString())}');
      if (stackTrace != null) {
        print('Stack trace:');
        print(_sanitizeStackTrace(stackTrace));
      }
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
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
