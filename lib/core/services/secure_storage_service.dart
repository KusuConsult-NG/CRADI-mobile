import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

/// Secure storage service using platform-specific secure storage
/// iOS: Keychain, Android: KeyStore, Web: Encrypted storage
class SecureStorageService {
  static final SecureStorageService _instance =
      SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // Keys for stored data
  static const String _keyAuthToken = 'auth_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyUserRole = 'user_role';
  static const String _keyPhoneNumber = 'phone_number';
  static const String _keySessionExpiry = 'session_expiry';
  static const String _keyLoginAttempts = 'login_attempts';
  static const String _keyLastLoginAttempt = 'last_login_attempt';
  static const String _keyAccountLockedUntil = 'account_locked_until';
  static const String _keyBiometricEnabled = 'biometric_enabled';

  /// User id of the account that enabled the biometric lock: the lock is
  /// per account, so it never carries over to another account signing in
  /// on a shared device.
  static const String _keyBiometricOwner = 'biometric_owner';
  static const String _keyRememberMe = 'remember_me';

  // Authentication token management
  Future<void> saveAuthToken(String token) async {
    await _storage.write(key: _keyAuthToken, value: token);
  }

  Future<String?> getAuthToken() async {
    return await _storage.read(key: _keyAuthToken);
  }

  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _keyRefreshToken, value: token);
  }

  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _keyRefreshToken);
  }

  // Legacy keys: older builds stored the plaintext email/password for
  // biometric re-login. Biometric unlock now reuses the persisted Supabase
  // session instead; these keys are only ever deleted.
  static const String _legacyKeyUserEmail = 'user_email';
  static const String _legacyKeyUserPassword = 'user_password';

  /// Remove credentials persisted by older app versions.
  Future<void> purgeLegacyCredentials() async {
    await _storage.delete(key: _legacyKeyUserEmail);
    await _storage.delete(key: _legacyKeyUserPassword);
  }

  // User data management
  Future<void> saveUserRole(String role) async {
    await _storage.write(key: _keyUserRole, value: role);
  }

  Future<String?> getUserRole() async {
    return await _storage.read(key: _keyUserRole);
  }

  Future<void> savePhoneNumber(String phone) async {
    await _storage.write(key: _keyPhoneNumber, value: phone);
  }

  Future<String?> getPhoneNumber() async {
    return await _storage.read(key: _keyPhoneNumber);
  }

  // Session management
  Future<void> saveRememberMe(bool rememberMe) async {
    await _storage.write(key: _keyRememberMe, value: rememberMe.toString());
  }

  Future<bool> getRememberMe() async {
    final value = await _storage.read(key: _keyRememberMe);
    return value == 'true';
  }

  Future<void> saveSessionExpiry(DateTime expiry) async {
    await _storage.write(
      key: _keySessionExpiry,
      value: expiry.toIso8601String(),
    );
  }

  Future<DateTime?> getSessionExpiry() async {
    final expiryStr = await _storage.read(key: _keySessionExpiry);
    if (expiryStr == null) return null;
    return DateTime.parse(expiryStr);
  }

  Future<bool> isSessionValid() async {
    final expiry = await getSessionExpiry();
    if (expiry == null) return false;
    return DateTime.now().isBefore(expiry);
  }

  // Rate limiting and account lockout
  Future<void> incrementLoginAttempts() async {
    final attempts = await getLoginAttempts();
    await _storage.write(
      key: _keyLoginAttempts,
      value: (attempts + 1).toString(),
    );
    await _storage.write(
      key: _keyLastLoginAttempt,
      value: DateTime.now().toIso8601String(),
    );
  }

  Future<int> getLoginAttempts() async {
    final attemptsStr = await _storage.read(key: _keyLoginAttempts);
    return int.tryParse(attemptsStr ?? '0') ?? 0;
  }

  Future<void> resetLoginAttempts() async {
    await _storage.delete(key: _keyLoginAttempts);
    await _storage.delete(key: _keyLastLoginAttempt);
  }

  Future<void> lockAccount(Duration lockDuration) async {
    final lockUntil = DateTime.now().add(lockDuration);
    await _storage.write(
      key: _keyAccountLockedUntil,
      value: lockUntil.toIso8601String(),
    );
  }

  Future<bool> isAccountLocked() async {
    final lockedUntilStr = await _storage.read(key: _keyAccountLockedUntil);
    if (lockedUntilStr == null) return false;

    final lockedUntil = DateTime.parse(lockedUntilStr);
    if (DateTime.now().isAfter(lockedUntil)) {
      // Lock expired, clear it
      await _storage.delete(key: _keyAccountLockedUntil);
      await resetLoginAttempts();
      return false;
    }
    return true;
  }

  Future<DateTime?> getAccountLockedUntil() async {
    final lockedUntilStr = await _storage.read(key: _keyAccountLockedUntil);
    if (lockedUntilStr == null) return null;
    return DateTime.parse(lockedUntilStr);
  }

  // Biometric settings
  /// Enables / disables the biometric lock for [userId] (the owner is
  /// recorded when enabling).
  Future<void> setBiometricEnabled(bool enabled, {String? userId}) async {
    await _storage.write(key: _keyBiometricEnabled, value: enabled.toString());
    if (enabled && userId != null) {
      await _storage.write(key: _keyBiometricOwner, value: userId);
    } else if (!enabled) {
      await _storage.delete(key: _keyBiometricOwner);
    }
  }

  /// Whether the biometric lock is enabled. With [forUserId], only when it
  /// was enabled by that account (flags written by older builds have no
  /// owner and count for whoever is signed in; see [bindBiometricOwner]).
  Future<bool> isBiometricEnabled({String? forUserId}) async {
    final enabledStr = await _storage.read(key: _keyBiometricEnabled);
    if (enabledStr != 'true') return false;
    if (forUserId == null) return true;
    final owner = await _storage.read(key: _keyBiometricOwner);
    return owner == null || owner == forUserId;
  }

  /// Ties the biometric flag to [userId]: an ownerless (legacy) flag is
  /// bound to it, and a flag enabled by another account is cleared.
  Future<void> bindBiometricOwner(String userId) async {
    final enabledStr = await _storage.read(key: _keyBiometricEnabled);
    if (enabledStr != 'true') return;
    final owner = await _storage.read(key: _keyBiometricOwner);
    if (owner == null) {
      await _storage.write(key: _keyBiometricOwner, value: userId);
    } else if (owner != userId) {
      await setBiometricEnabled(false);
    }
  }

  // Generic secure storage
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  // Store complex objects as JSON
  Future<void> writeJson(String key, Map<String, dynamic> value) async {
    await _storage.write(key: key, value: json.encode(value));
  }

  Future<Map<String, dynamic>?> readJson(String key) async {
    final jsonStr = await _storage.read(key: key);
    if (jsonStr == null) return null;
    return json.decode(jsonStr) as Map<String, dynamic>;
  }

  /// Keys holding the signed-in user's session / identity data.
  static const List<String> _sessionKeys = [
    _keyAuthToken,
    _keyRefreshToken,
    _keyUserRole,
    _keySessionExpiry,
    _keyRememberMe,
    _legacyKeyUserEmail,
    _legacyKeyUserPassword,
  ];

  /// Clears secure data on logout.
  ///
  /// Only this service's own keys are deleted — never `deleteAll()`: the
  /// keystore also holds the Hive encryption key (`hive_encryption_key`,
  /// see HiveEncryptionService), which must survive a logout or every
  /// encrypted Hive box becomes unreadable on the next launch. Login-attempt
  /// / lockout counters are kept too, so logging out cannot reset them.
  ///
  /// [keepAuth] preserves the auth token and user info (biometric login).
  /// [keepPreferences] preserves the biometric preference (and, when it is
  /// enabled, the phone number).
  Future<void> clearAll({
    bool keepAuth = false,
    bool keepPreferences = false,
  }) async {
    final keys = <String>[
      _keySessionExpiry,
      if (!keepAuth) ..._sessionKeys.where((k) => k != _keySessionExpiry),
    ];

    final keepPhone = keepPreferences && await isBiometricEnabled();
    if (!keepAuth && !keepPhone) keys.add(_keyPhoneNumber);
    if (!keepPreferences) {
      keys.addAll([_keyBiometricEnabled, _keyBiometricOwner]);
    }

    for (final key in keys) {
      await _storage.delete(key: key);
    }
  }

  // Clear only authentication data
  Future<void> clearAuthData() async {
    await _storage.delete(key: _keyAuthToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keySessionExpiry);
  }
}
