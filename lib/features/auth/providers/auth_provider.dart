import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/session_manager.dart';
import 'package:climate_app/core/services/rate_limiter.dart';
import 'package:climate_app/core/services/biometric_service.dart';
import 'package:climate_app/core/services/encryption_service.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'dart:math';

enum UserRole { ewm, coordinator, projectStaff, earlyResponder, media }

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  UserRole? _userRole;
  String? _registrationCode;
  String? _phoneNumber;
  bool _isLoading = false;
  String? _currentOtp;
  DateTime? _otpExpiry;

  // Services
  final SecureStorageService _storage = SecureStorageService();
  final SessionManager _sessionManager = SessionManager();
  final RateLimiter _rateLimiter = RateLimiter();
  final BiometricService _biometricService = BiometricService();
  final EncryptionService _encryptionService = EncryptionService();

  bool get isAuthenticated => _isAuthenticated;
  UserRole? get userRole => _userRole;
  bool get isLoading => _isLoading;
  String? get phoneNumber => _phoneNumber;

  AuthProvider() {
    _initializeSessionManager();
    _checkExistingSession();
  }

  void _initializeSessionManager() {
    _sessionManager.onSessionExpired = () {
      logout();
      // Notify listeners to show session expired dialog
      notifyListeners();
    };
  }

  /// Check for existing valid session on app start
  Future<void> _checkExistingSession() async {
    try {
      final resumed = await _sessionManager.resumeSession();
      if (resumed) {
        final userRoleStr = await _storage.getUserRole();
        final phoneNumber = await _storage.getPhoneNumber();

        if (userRoleStr != null) {
          _isAuthenticated = true;
          _userRole = _parseUserRole(userRoleStr);
          _phoneNumber = phoneNumber;
          notifyListeners();
        }
      }
    } catch (e) {
      ErrorHandler.logError(e, context: 'AuthProvider._checkExistingSession');
    }
  }

  /// Verify registration code and phone number
  /// In production, this should call a backend API
  Future<bool> verifyRegistrationCode(String code, String phone) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Check rate limiting
      final rateLimitResult = await _rateLimiter.checkLoginAttempt();
      if (!rateLimitResult.allowed) {
        throw AuthException(rateLimitResult.userMessage);
      }

      // Simulate API delay
      await Future.delayed(const Duration(seconds: 1));

      // SECURE: In production, this should verify against backend API
      // For now, using secure mock validation
      final isValid = await _mockVerifyCode(code);

      if (isValid) {
        _registrationCode = code;
        _phoneNumber = phone;

        // Reset login attempts on successful verification
        await _rateLimiter.resetLoginAttempts();

        // Generate and store OTP
        _generateOTP();

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        // Record failed attempt
        await _rateLimiter.recordFailedLogin();

        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.verifyRegistrationCode');
      rethrow;
    }
  }

  /// Mock code verification (replace with real API call)
  Future<bool> _mockVerifyCode(String code) async {
    // SECURE: Valid codes should come from backend
    // These are just examples for testing
    final validCodes = {
      'EWM123': UserRole.ewm,
      'COORD456': UserRole.coordinator,
      'ADMIN789': UserRole.projectStaff,
      'RESP999': UserRole.earlyResponder,
      'MEDIA888': UserRole.media,
    };

    return validCodes.containsKey(code.toUpperCase());
  }

  /// Generate secure OTP
  void _generateOTP() {
    // Generate random 4-digit OTP
    final random = Random.secure();
    _currentOtp = (1000 + random.nextInt(9000)).toString();
    _otpExpiry = DateTime.now().add(const Duration(minutes: 5));

    // In production, send OTP via SMS/backend
    // For testing, log to console (only in debug mode)
    if (!const bool.fromEnvironment('dart.vm.product')) {
      developer.log(
        '🔐 DEBUG OTP: $_currentOtp (expires at ${_otpExpiry!.toLocal()})',
        name: 'AuthProvider',
      );
    }
  }

  /// Verify OTP code
  Future<bool> verifyOTP(String otp) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Check OTP expiry
      if (_otpExpiry == null || DateTime.now().isAfter(_otpExpiry!)) {
        throw AuthException('OTP has expired. Please request a new code.');
      }

      // Check rate limiting
      final rateLimitResult = await _rateLimiter.checkLoginAttempt();
      if (!rateLimitResult.allowed) {
        throw AuthException(rateLimitResult.userMessage);
      }

      // Simulate API delay
      await Future.delayed(const Duration(seconds: 1));

      // Verify OTP
      if (otp == _currentOtp) {
        // Get user role from registration code
        final role = await _getUserRoleFromCode(_registrationCode!);

        // Generate auth token (in production, this comes from backend)
        final authToken = _encryptionService.generateSecureToken();

        // Save authentication data
        await _storage.saveAuthToken(authToken);
        await _storage.saveUserRole(role.name);
        await _storage.savePhoneNumber(_phoneNumber!);

        // Start session
        await _sessionManager.startSession(
          authToken: authToken,
          userRole: role.name,
        );

        // Reset rate limiter
        await _rateLimiter.resetLoginAttempts();

        // Update state
        _isAuthenticated = true;
        _userRole = role;

        // Clear OTP
        _currentOtp = null;
        _otpExpiry = null;

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        // Record failed attempt
        await _rateLimiter.recordFailedLogin();

        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.verifyOTP');
      rethrow;
    }
  }

  /// Resend OTP
  Future<bool> resendOTP(String phoneNumber) async {
    try {
      // Check rate limiting for OTP requests
      final rateLimitResult = await _rateLimiter.checkOtpRequest(phoneNumber);
      if (!rateLimitResult.allowed) {
        throw AuthException(rateLimitResult.userMessage);
      }

      // Generate new OTP
      _generateOTP();

      // Record the OTP request
      await _rateLimiter.recordOtpRequest(phoneNumber);

      notifyListeners();
      return true;
    } catch (e) {
      ErrorHandler.logError(e, context: 'AuthProvider.resendOTP');
      rethrow;
    }
  }

  /// Get user role from registration code (mock - should be from backend)
  Future<UserRole> _getUserRoleFromCode(String code) async {
    final roleMap = {
      'EWM123': UserRole.ewm,
      'COORD456': UserRole.coordinator,
      'ADMIN789': UserRole.projectStaff,
      'RESP999': UserRole.earlyResponder,
      'MEDIA888': UserRole.media,
    };

    return roleMap[code.toUpperCase()] ?? UserRole.ewm;
  }

  /// Authenticate with biometrics
  Future<bool> authenticateWithBiometrics() async {
    try {
      final isBiometricEnabled = await _storage.isBiometricEnabled();
      if (!isBiometricEnabled) {
        return false;
      }

      final authenticated = await _biometricService.authenticateForLogin();

      if (authenticated) {
        // Check if we have a preserved auth token
        final authToken = await _storage.getAuthToken();

        // If authToken is null, it means session really expired or logout cleared it too aggressively.
        // For biometrics to work after logout, we need to KEEP the token (or a refresh token) in secure storage
        // even after logout, IF biometrics is enabled.

        if (authToken != null) {
          // Valid user returning with biometrics
          _isAuthenticated = true;

          final userRoleStr = await _storage.getUserRole();
          _userRole = _parseUserRole(userRoleStr);

          final phoneNumber = await _storage.getPhoneNumber();
          _phoneNumber = phoneNumber;

          // Start a new session
          await _sessionManager.startSession(
            authToken: authToken,
            userRole: userRoleStr,
          );

          notifyListeners();
          return true;
        } else {
          // Token was missing.
          developer.log(
            'Biometric auth success but no token found',
            name: 'AuthProvider',
          );
          // In a real app, we might prompt for PIN or Password here if token is gone.
          // Or, we should have never cleared the token in logout() if bio was enabled.
          return false;
        }
      }

      return false;
    } catch (e) {
      ErrorHandler.logError(
        e,
        context: 'AuthProvider.authenticateWithBiometrics',
      );
      return false;
    }
  }

  /// Enable/disable biometric authentication
  Future<void> setBiometricEnabled(bool enabled) async {
    if (enabled) {
      // Test biometric authentication before enabling
      final canAuthenticate = await _biometricService.authenticate(
        reason: 'Enable biometric login for CRADI Mobile',
      );

      if (canAuthenticate) {
        await _storage.setBiometricEnabled(true);
      } else {
        throw AuthException('Biometric authentication failed');
      }
    } else {
      await _storage.setBiometricEnabled(false);
      // If disabling biometrics, we might want to clear preserved auth data meant for it?
      // But for now, just disabling the flag is enough.
    }
    notifyListeners();
  }

  /// Check if biometric is enabled
  Future<bool> isBiometricEnabled() async {
    return await _storage.isBiometricEnabled();
  }

  /// Check if biometric is available
  Future<bool> isBiometricAvailable() async {
    return await _biometricService.isBiometricAvailable();
  }

  /// Record user activity for session management
  void recordActivity() {
    if (_isAuthenticated) {
      _sessionManager.recordActivity();
    }
  }

  /// Get remaining session time
  Future<Duration?> getSessionTimeRemaining() async {
    return await _sessionManager.getRemainingTime();
  }

  /// Logout
  Future<void> logout() async {
    try {
      await _sessionManager.logout();

      // Keep phone number if biometrics is enabled so we can re-login
      final bioEnabled = await _storage.isBiometricEnabled();
      if (bioEnabled) {
        // Phone number should be preserved by SessionManager.logout if implemented correctly there,
        // but let's ensure our local state reflects that we are logged out but might know the user.
        // Actually, local state _phoneNumber should probably be cleared from memory to force re-login/re-fetch,
        // but the storage keeps it.
      } else {
        _phoneNumber = null;
      }

      _isAuthenticated = false;
      _userRole = null;
      _registrationCode = null;
      // _phoneNumber = null; // Don't nullify immediately if we want to show "Welcome back, 080..."?
      // User requested "biomatrics doesn't work after logout and trying to login again".
      // This usually means the data needed to re-authenticate (like token or phone to lookup) is gone.

      // If we are strictly following "logout clears everything", then biometrics can't work without a fresh login.
      // But "Log in with Biometrics" implies we have a stashed token or credentials.

      _currentOtp = null;
      _otpExpiry = null;

      notifyListeners();
    } catch (e) {
      ErrorHandler.logError(e, context: 'AuthProvider.logout');
    }
  }

  /// Parse user role from string
  UserRole? _parseUserRole(String? roleStr) {
    if (roleStr == null) return null;

    try {
      return UserRole.values.firstWhere((role) => role.name == roleStr);
    } catch (e) {
      return null;
    }
  }

  /// Get current OTP expiry time remaining (for UI)
  Duration? getOtpExpiryRemaining() {
    if (_otpExpiry == null) return null;

    final remaining = _otpExpiry!.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  @override
  void dispose() {
    _sessionManager.dispose();
    super.dispose();
  }
}
