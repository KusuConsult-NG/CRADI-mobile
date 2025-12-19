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
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
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
  static const String _keyVerificationEmail = 'verification_email';

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
  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(key: _keyBiometricEnabled, value: enabled.toString());
  }

  Future<bool> isBiometricEnabled() async {
    final enabledStr = await _storage.read(key: _keyBiometricEnabled);
    return enabledStr == 'true';
  }

  // Email verification storage (for email link auth)
  static Future<void> saveVerificationEmail(String email) async {
    final instance = SecureStorageService();
    await instance.write(_keyVerificationEmail, email);
  }

  static Future<String?> getVerificationEmail() async {
    final instance = SecureStorageService();
    return await instance.read(_keyVerificationEmail);
  }

  static Future<void> deleteVerificationEmail() async {
    final instance = SecureStorageService();
    await instance.delete(_keyVerificationEmail);
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

  // Clear all secure data (logout)
  /// [keepAuth] if true, preserves auth token and user info for biometric login
  /// [keepPreferences] if true, preserves user preferences like biometric enabled status
  Future<void> clearAll({
    bool keepAuth = false,
    bool keepPreferences = false,
  }) async {
    if (keepAuth && keepPreferences) {
      // Only clear temporary session data
      await _storage.delete(key: _keySessionExpiry);
      await _storage.delete(key: _keyLoginAttempts);
      await _storage.delete(key: _keyLastLoginAttempt);
      await _storage.delete(key: _keyAccountLockedUntil);
      return;
    }

    if (keepPreferences) {
      // Keep preferences like biometric enabled, but clear auth and user data
      final biometricEnabled = await isBiometricEnabled();
      final phoneNumber = await getPhoneNumber();

      await _storage.deleteAll();

      // Restore selected preferences
      if (biometricEnabled) {
        await setBiometricEnabled(true);
        if (phoneNumber != null) {
          await savePhoneNumber(phoneNumber);
        }
      }
      return;
    }

    // Default: Clear absolutely everything
    await _storage.deleteAll();
  }

  // Clear only authentication data
  Future<void> clearAuthData() async {
    await _storage.delete(key: _keyAuthToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keySessionExpiry);
  }
}
