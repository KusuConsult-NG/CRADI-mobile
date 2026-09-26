import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// Secure error handler that prevents sensitive data leakage
class ErrorHandler {
  /// Get a user-friendly error message in the language of [l10n].
  static String getUserMessage(dynamic error, AppLocalizations l10n) {
    if (kReleaseMode) {
      return genericMessage(error, l10n);
    }
    return _getDetailedMessage(error, l10n);
  }

  /// Get generic user-friendly message (release builds).
  ///
  /// Exposed for tests: the release path is unreachable from a test binary
  /// (`kReleaseMode` is false there), so the scrubbing below would
  /// otherwise never be exercised.
  /// IMPORTANT: SDK-internal messages must NEVER be surfaced raw to the user —
  /// they leak implementation detail and confuse end users.
  @visibleForTesting
  static String genericMessage(dynamic error, AppLocalizations l10n) {
    // Only the app's own exceptions carry a curated, user-facing message.
    // (A runtimeType name check would also match Supabase's AuthException,
    // whose raw server message must not be shown.)
    if (error is SecureException) {
      return error.userMessage(l10n);
    }

    final msg = error.toString().toLowerCase();
    // Network / connectivity
    if (msg.contains('network') ||
        msg.contains('socket') ||
        msg.contains('connection')) {
      return l10n.errorNetwork;
    }
    // Permission / access
    if (msg.contains('permission') || msg.contains('denied')) {
      return l10n.errorNoPermission;
    }
    // SDK internal strings — must be scrubbed
    if (msg.contains('internal error') ||
        msg.contains('postgrest') ||
        msg.contains('authapiexception')) {
      return l10n.errorContactSupport;
    }
    return l10n.errorUnexpected;
  }

  /// Get detailed message (debug mode only). The app's own exceptions still
  /// show their curated (translated) text; anything else shows the raw error
  /// for developers.
  static String _getDetailedMessage(dynamic error, AppLocalizations l10n) {
    if (error is SecureException) {
      return error.userMessage(l10n);
    }
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
        'Error: ${sanitizeForLog(error.toString())}',
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

  /// Sanitize log output to remove sensitive data.
  ///
  /// Exposed for tests: it only runs inside debug logging and the
  /// release-only crash reporter, neither of which a test can observe.
  @visibleForTesting
  static String sanitizeForLog(String log) {
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
    return sanitizeForLog(stackTrace.toString());
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
    final sanitizedError = sanitizeForLog(error.toString());
    Sentry.captureMessage(
      context != null ? '[$context] $sanitizedError' : sanitizedError,
      level: SentryLevel.error,
    );
  }

  /// Handle and display error to user
  static String handleError(
    dynamic error,
    AppLocalizations l10n, {
    String? context,
  }) {
    logError(error, context: context);
    return getUserMessage(error, l10n);
  }
}

/// Custom secure exception. [userMessage] is resolved against the current
/// locale's strings where it is shown (see [ErrorHandler.getUserMessage]).
class SecureException implements Exception {
  final LocalizedText userMessage;
  final String? technicalDetails;

  SecureException(this.userMessage, {this.technicalDetails});

  /// The message in English, for logs and tests (never for the UI).
  String get englishMessage => userMessage(englishL10n);

  @override
  String toString() {
    if (kDebugMode && technicalDetails != null) {
      return 'SecureException: $englishMessage\nDetails: $technicalDetails';
    }
    return englishMessage;
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
    : super((l) => l.authEmailNotConfirmed(email));
  final String email;
}

/// Validation exception
class ValidationException extends SecureException {
  ValidationException(super.userMessage, {super.technicalDetails});
}

/// Storage exception
class StorageException extends SecureException {
  StorageException(super.userMessage, {super.technicalDetails});
}
