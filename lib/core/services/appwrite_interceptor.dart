import 'package:appwrite/appwrite.dart';
import 'dart:developer' as developer;

/// Wrapper around Appwrite operations with automatic session handling
///
/// This interceptor provides centralized 401/403 error handling for all
/// Appwrite operations, implementing automatic session validation and
/// graceful re-authentication when sessions expire.
class AppwriteInterceptor {
  final Account _account;
  final Function(AppwriteException) onSessionExpired;

  AppwriteInterceptor({
    required Account account,
    required this.onSessionExpired,
  }) : _account = account;

  /// Execute operation with automatic 401/403 handling
  ///
  /// This method wraps any Appwrite operation and:
  /// 1. Executes the operation normally
  /// 2. If 401/403 error occurs, validates the session
  /// 3. If session is valid, retries the operation once
  /// 4. If session is invalid, triggers logout callback
  Future<T> execute<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AppwriteException catch (e) {
      if (e.code == 401 || e.code == 403) {
        developer.log(
          'Session expired (${e.code}): ${e.message}',
          name: 'AppwriteInterceptor',
        );

        // Attempt session validation
        final isValid = await _validateSession();
        if (isValid) {
          developer.log(
            'Session validation successful, retrying operation',
            name: 'AppwriteInterceptor',
          );
          // Retry operation once
          try {
            return await operation();
          } catch (retryError) {
            // If retry fails, trigger logout
            developer.log(
              'Retry failed after session validation',
              name: 'AppwriteInterceptor',
            );
            onSessionExpired(e);
            rethrow;
          }
        } else {
          // Session truly expired - trigger logout
          developer.log(
            'Session validation failed - triggering logout',
            name: 'AppwriteInterceptor',
          );
          onSessionExpired(e);
          rethrow;
        }
      }
      rethrow;
    }
  }

  /// Validate current session by attempting to fetch user
  Future<bool> _validateSession() async {
    try {
      await _account.get();
      return true;
    } on Exception catch (e) {
      developer.log(
        'Session validation error: $e',
        name: 'AppwriteInterceptor',
      );
      return false;
    }
  }
}
