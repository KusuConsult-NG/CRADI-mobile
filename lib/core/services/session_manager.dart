import 'secure_storage_service.dart';
import 'dart:async';

/// Session manager for handling user sessions and automatic logout
class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  final SecureStorageService _storage = SecureStorageService();

  // Session configuration
  static const Duration sessionTimeout = Duration(minutes: 30);
  static const Duration sessionExtensionThreshold = Duration(minutes: 5);

  Timer? _sessionTimer;
  Timer? _activityTimer;

  /// Callbacks
  Function? onSessionExpired;
  Function? onSessionExtended;

  /// Start a new session
  Future<void> startSession({String? authToken, String? userRole}) async {
    final expiry = DateTime.now().add(sessionTimeout);
    await _storage.saveSessionExpiry(expiry);

    if (authToken != null) {
      await _storage.saveAuthToken(authToken);
    }

    if (userRole != null) {
      await _storage.saveUserRole(userRole);
    }

    _startSessionTimer();
  }

  /// Extend current session
  Future<void> extendSession() async {
    final expiry = DateTime.now().add(sessionTimeout);
    await _storage.saveSessionExpiry(expiry);

    onSessionExtended?.call();
  }

  /// Record user activity to extend session
  void recordActivity() {
    // Auto-extend session if close to expiry
    _checkAndExtendSession();
  }

  /// Check if session should be extended
  Future<void> _checkAndExtendSession() async {
    final expiry = await _storage.getSessionExpiry();
    if (expiry == null) return;

    final timeUntilExpiry = expiry.difference(DateTime.now());

    // Extend session if within threshold and user is active
    if (timeUntilExpiry < sessionExtensionThreshold &&
        timeUntilExpiry > Duration.zero) {
      await extendSession();
    }
  }

  /// Start session expiry timer
  void _startSessionTimer() {
    _sessionTimer?.cancel();

    _sessionTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkSessionExpiry(),
    );
  }

  /// Check if session has expired
  Future<void> _checkSessionExpiry() async {
    final isValid = await _storage.isSessionValid();

    if (!isValid) {
      await endSession(expired: true);
    }
  }

  /// Get remaining session time
  Future<Duration?> getRemainingTime() async {
    final expiry = await _storage.getSessionExpiry();
    if (expiry == null) return null;

    final remaining = expiry.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Check if session is valid
  Future<bool> isSessionValid() async {
    return await _storage.isSessionValid();
  }

  /// End current session
  Future<void> endSession({bool expired = false}) async {
    _sessionTimer?.cancel();
    _activityTimer?.cancel();

    // If just ending session (not full logout), we might want to keep auth data
    // based on implementation. But generally endSession means session is over.
    // Use logout for user-initiated action.

    // For simple session expiry, we just clear session expiry time?
    // Actually, existing behavior was clearAuthData.

    await _storage.clearAuthData();

    if (expired) {
      onSessionExpired?.call();
    }
  }

  /// Logout and clear all data
  Future<void> logout() async {
    _sessionTimer?.cancel();
    _activityTimer?.cancel();

    // Check if biometric is enabled
    final biometricEnabled = await _storage.isBiometricEnabled();

    // Clear data but preserve preferences and auth if biometric is enabled
    // keeping auth allows "Login with Biometrics" to work (needs token to resume session)
    await _storage.clearAll(
      keepAuth: biometricEnabled,
      keepPreferences:
          true, // Always keep preferences (like language) if possible? Or just for biometric users. Plan said preserve biometric.
    );
  }

  /// Dispose timers
  void dispose() {
    _sessionTimer?.cancel();
    _activityTimer?.cancel();
  }

  /// Get session info
  Future<SessionInfo?> getSessionInfo() async {
    final expiry = await _storage.getSessionExpiry();
    final authToken = await _storage.getAuthToken();
    final userRole = await _storage.getUserRole();
    final phoneNumber = await _storage.getPhoneNumber();

    if (expiry == null || authToken == null) {
      return null;
    }

    return SessionInfo(
      authToken: authToken,
      userRole: userRole,
      phoneNumber: phoneNumber,
      expiry: expiry,
      isValid: DateTime.now().isBefore(expiry),
    );
  }

  /// Resume session on app restart
  Future<bool> resumeSession() async {
    final isValid = await isSessionValid();

    if (isValid) {
      _startSessionTimer();
      return true;
    }

    return false;
  }
}

/// Session information model
class SessionInfo {
  final String authToken;
  final String? userRole;
  final String? phoneNumber;
  final DateTime expiry;
  final bool isValid;

  SessionInfo({
    required this.authToken,
    this.userRole,
    this.phoneNumber,
    required this.expiry,
    required this.isValid,
  });

  Duration get timeRemaining => expiry.difference(DateTime.now());
}
