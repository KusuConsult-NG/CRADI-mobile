import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// Biometric authentication service
///
/// local_auth 3.x reports failures as [LocalAuthException] (not
/// [PlatformException]); both are caught, and the code of the latest
/// failure is kept in [lastErrorCode] so the UI can explain it.
class BiometricService {
  static final BiometricService _instance = BiometricService._internal();
  factory BiometricService() => _instance;
  BiometricService._internal([LocalAuthentication? localAuth])
    : _localAuth = localAuth ?? LocalAuthentication();

  /// A separate instance backed by [localAuth] (tests only).
  @visibleForTesting
  factory BiometricService.withLocalAuth(LocalAuthentication localAuth) =>
      BiometricService._internal(localAuth);

  final LocalAuthentication _localAuth;

  /// Code of the most recent failed call, or null after a call that did
  /// not throw.
  LocalAuthExceptionCode? lastErrorCode;

  /// Whether the latest failure means no biometrics / device credentials
  /// are enrolled (the user has to add them in the device settings).
  bool get lastErrorIsNotEnrolled => isNotEnrolledCode(lastErrorCode);

  static bool isNotEnrolledCode(LocalAuthExceptionCode? code) =>
      code == LocalAuthExceptionCode.noBiometricsEnrolled ||
      code == LocalAuthExceptionCode.noCredentialsSet;

  /// User-facing text for a failure [code]; null for a user cancellation
  /// (nothing to explain) or when there was no failure.
  static LocalizedText? messageFor(LocalAuthExceptionCode? code) {
    switch (code) {
      case null:
      case LocalAuthExceptionCode.userCanceled:
      case LocalAuthExceptionCode.systemCanceled:
        return null;
      case LocalAuthExceptionCode.noBiometricsEnrolled:
      case LocalAuthExceptionCode.noCredentialsSet:
        return (l) => l.biometricErrorNotEnrolled;
      case LocalAuthExceptionCode.noBiometricHardware:
      case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
        return (l) => l.biometricErrorUnavailable;
      case LocalAuthExceptionCode.temporaryLockout:
      case LocalAuthExceptionCode.biometricLockout:
        return (l) => l.biometricErrorLockedOut;
      default:
        return (l) => l.biometricErrorFailed;
    }
  }

  void _recordError(Object e) {
    lastErrorCode = e is LocalAuthException
        ? e.code
        : LocalAuthExceptionCode.unknownError;
  }

  /// Check if biometric authentication is available on device
  Future<bool> isBiometricAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } on LocalAuthException catch (e) {
      _recordError(e);
      developer.log(
        'Error checking biometric availability: $e',
        name: 'BiometricService',
      );
      return false;
    } on PlatformException catch (e) {
      developer.log(
        'Error checking biometric availability: $e',
        name: 'BiometricService',
      );
      return false;
    }
  }

  /// Whether biometric login can actually be offered on this device:
  /// the hardware can be queried *and* the user has enrolled a fingerprint
  /// or face. Hardware without an enrolment can only fail at the prompt, so
  /// every screen that offers the setting asks this first and disables the
  /// control instead.
  Future<bool> isBiometricUsable() async {
    if (!await isBiometricAvailable()) return false;
    return (await getAvailableBiometrics()).isNotEmpty;
  }

  /// Check if device has biometric hardware
  Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } on LocalAuthException catch (e) {
      _recordError(e);
      developer.log(
        'Error checking device support: $e',
        name: 'BiometricService',
      );
      return false;
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
    } on LocalAuthException catch (e) {
      _recordError(e);
      developer.log(
        'Error getting available biometrics: $e',
        name: 'BiometricService',
      );
      return [];
    } on PlatformException catch (e) {
      developer.log(
        'Error getting available biometrics: $e',
        name: 'BiometricService',
      );
      return [];
    }
  }

  /// Authenticate using biometrics. [reason] is shown in the system prompt;
  /// UI callers pass it localised (the English default is a fallback).
  Future<bool> authenticate({
    String? reason,
    bool useErrorDialogs = true,
    bool stickyAuth = true,
  }) async {
    lastErrorCode = null;
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        lastErrorCode ??= LocalAuthExceptionCode.noBiometricHardware;
        return false;
      }

      return await _localAuth.authenticate(
        localizedReason: reason ?? englishL10n.biometricPromptDefault,
      );
    } on LocalAuthException catch (e) {
      _recordError(e);
      developer.log('Authentication error: $e', name: 'BiometricService');
      return false;
    } on PlatformException catch (e) {
      _recordError(e);
      developer.log('Authentication error: $e', name: 'BiometricService');
      return false;
    }
  }

  /// Authenticate for login; [reason] is the localised system-prompt text.
  Future<bool> authenticateForLogin({String? reason}) async {
    return await authenticate(
      reason: reason,
      useErrorDialogs: true,
      stickyAuth: true,
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
  String getBiometricTypeName(BiometricType type, AppLocalizations l10n) {
    switch (type) {
      case BiometricType.face:
        return l10n.biometricTypeFace;
      case BiometricType.fingerprint:
        return l10n.biometricTypeFingerprint;
      case BiometricType.iris:
        return l10n.biometricTypeIris;
      case BiometricType.strong:
      case BiometricType.weak:
        return l10n.biometricTypeGeneric;
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
}
