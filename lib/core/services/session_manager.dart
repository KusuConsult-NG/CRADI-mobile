import 'secure_storage_service.dart';
import 'dart:async';

/// Inactivity timeout on top of the Supabase session.
///
/// The expiry is pushed forward by user activity ([recordActivity], wired to
/// a root pointer listener and route changes in `main.dart`), so it is an
/// *inactivity* timeout: [onSessionExpired] fires only after [sessionTimeout]
/// (or [persistentSessionTimeout] with "remember me") without interaction.
class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  final SecureStorageService _storage = SecureStorageService();

  // Session configuration
  static const Duration sessionTimeout = Duration(minutes: 30);
  static const Duration persistentSessionTimeout = Duration(days: 30);

  /// Minimum interval between two activity-driven expiry extensions (each
  /// one writes to secure storage).
  static const Duration activityThrottle = Duration(minutes: 1);

  Timer? _sessionTimer;
  Timer? _activityTimer;
  DateTime? _lastActivityExtension;

  /// Callbacks
  Function? onSessionExpired;
  Function? onSessionExtended;

  /// Start a new session
  Future<void> startSession({
    String? authToken,
    String? userRole,
    bool rememberMe = false,
  }) async {
    await _storage.saveRememberMe(rememberMe);

    final timeout = rememberMe ? persistentSessionTimeout : sessionTimeout;
    final expiry = DateTime.now().add(timeout);
    await _storage.saveSessionExpiry(expiry);

    if (authToken != null) {
      await _storage.saveAuthToken(authToken);
    }

    if (userRole != null) {
      await _storage.saveUserRole(userRole);
    }

    _startSessionTimer();
  }

  /// Extend the current session (restarting the expiry timer, which is
  /// stopped once a session has expired).
  Future<void> extendSession() async {
    final rememberMe = await _storage.getRememberMe();
    final timeout = rememberMe ? persistentSessionTimeout : sessionTimeout;
    final expiry = DateTime.now().add(timeout);
    await _storage.saveSessionExpiry(expiry);
    _lastActivityExtension = DateTime.now();
    if (_sessionTimer == null || !_sessionTimer!.isActive) {
      _startSessionTimer();
    }

    onSessionExtended?.call();
  }

  /// Record user activity: pushes the inactivity expiry forward (throttled
  /// to one storage write per [activityThrottle]).
  void recordActivity() {
    final now = DateTime.now();
    final last = _lastActivityExtension;
    if (last != null && now.difference(last) < activityThrottle) return;
    _lastActivityExtension = now;
    unawaited(_extendIfActive());
  }

  /// Extends a still-valid session; an expired one stays expired (the
  /// timer will lock / sign out).
  Future<void> _extendIfActive() async {
    final expiry = await _storage.getSessionExpiry();
    if (expiry == null || !DateTime.now().isBefore(expiry)) return;
    await extendSession();
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
    cancelTimers();

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
    cancelTimers();

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

  /// Stops the expiry timer (e.g. after a sign-out from elsewhere).
  void cancelTimers() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _activityTimer?.cancel();
    _lastActivityExtension = null;
  }

  /// Dispose timers
  void dispose() => cancelTimers();

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
