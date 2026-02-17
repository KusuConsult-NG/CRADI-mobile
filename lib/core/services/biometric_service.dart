import 'dart:developer' as developer;
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Biometric authentication service
class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _sessionTokenKey = 'biometric_session_token';

  /// Check if biometric authentication is available on device
  Future<bool> isBiometricAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } on PlatformException catch (e) {
      developer.log(
        'Error checking biometric availability: $e',
        name: 'BiometricService',
      );
      return false;
    }
  }

  /// Check if device has biometric hardware
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } on PlatformException catch (e) {
      developer.log(
        'Error checking device support: $e',
        name: 'BiometricService',
      );
      return false;
    }
  }

  /// Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException catch (e) {
      developer.log(
        'Error getting available biometrics: $e',
        name: 'BiometricService',
      );
      return [];
    }
  }

  /// Authenticate using biometrics
  Future<bool> authenticate({
    String reason = 'Please authenticate to continue',
    bool useErrorDialogs = true,
    bool stickyAuth = true,
  }) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        return false;
      }

      return await _localAuth.authenticate(localizedReason: reason);
    } on PlatformException catch (e) {
      developer.log('Authentication error: $e', name: 'BiometricService');
      return false;
    }
  }

  /// Authenticate for login
  Future<bool> authenticateForLogin() async {
    return await authenticate(
      reason: 'Authenticate to login to EWER Mobile',
      useErrorDialogs: true,
      stickyAuth: true,
    );
  }

  /// Authenticate for sensitive operations
  Future<bool> authenticateForSensitiveOperation(String operation) async {
    return await authenticate(
      reason: 'Authenticate to $operation',
      useErrorDialogs: true,
      stickyAuth: false,
    );
  }

  /// Stop authentication
  Future<void> stopAuthentication() async {
    try {
      await _localAuth.stopAuthentication();
    } on Exception catch (e) {
      developer.log(
        'Error stopping authentication: $e',
        name: 'BiometricService',
      );
    }
  }

  /// Get biometric type name for UI display
  String getBiometricTypeName(BiometricType type) {
    switch (type) {
      case BiometricType.face:
        return 'Face ID';
      case BiometricType.fingerprint:
        return 'Fingerprint';
      case BiometricType.iris:
        return 'Iris';
      case BiometricType.strong:
        return 'Biometric';
      case BiometricType.weak:
        return 'Biometric';
    }
  }

  /// Check if face ID is available
  Future<bool> isFaceIdAvailable() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.contains(BiometricType.face);
  }

  /// Check if fingerprint is available
  Future<bool> isFingerprintAvailable() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.contains(BiometricType.fingerprint);
  }

  /// Securely store session token
  Future<void> secureSessionToken(String token) async {
    await _storage.write(
      key: _sessionTokenKey,
      value: token,
      aOptions: const AndroidOptions(),
      iOptions: const IOSOptions(accessibility: KeychainAccessibility.passcode),
    );
  }

  /// Retrieve session token (requires biometric auth)
  Future<String?> getSessionToken() async {
    // 1. Check if token exists first
    final hasToken = await _storage.containsKey(key: _sessionTokenKey);
    if (!hasToken) return null;

    // 2. Require Biometric Auth to "Unlock"
    final isAuthenticated = await authenticate(
      reason: 'Scan fingerprint to unlock your session',
    );

    if (isAuthenticated) {
      return await _storage.read(key: _sessionTokenKey);
    }
    return null;
  }

  /// Clear session token
  Future<void> clearSessionToken() async {
    await _storage.delete(key: _sessionTokenKey);
  }
}
