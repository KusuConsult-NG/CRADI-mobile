import 'dart:developer' as developer;
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/session_manager.dart';
import 'package:climate_app/core/services/rate_limiter.dart';
import 'package:climate_app/core/services/biometric_service.dart';
import 'package:climate_app/core/services/device_fingerprint_service.dart';
import 'package:climate_app/core/services/fraud_detection_service.dart';
import 'package:climate_app/core/utils/error_handler.dart';

enum UserRole { ewm, coordinator, projectStaff, earlyResponder, media }

/// Provider for managing user authentication state and operations
///
/// Handles Appwrite authentication, biometric login, session management,
/// and user role-based access control.
class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    _initializeSessionManager();
    _checkExistingSession();
  }

  final AppwriteService _appwrite = AppwriteService();
  bool _isAuthenticated = false;
  UserRole? _userRole;
  String? _phoneToken;
  String? _emailToken;
  String? _phoneNumber;
  bool _isLoading = false;
  models.User? _currentUser;

  // Services
  final SecureStorageService _storage = SecureStorageService();
  final SessionManager _sessionManager = SessionManager();
  final RateLimiter _rateLimiter = RateLimiter();
  final BiometricService _biometricService = BiometricService();
  // Security services
  final DeviceFingerprintService _fingerprintService =
      DeviceFingerprintService();
  final FraudDetectionService _fraudService = FraudDetectionService();

  bool get isAuthenticated => _isAuthenticated;
  UserRole? get userRole => _userRole;
  bool get isLoading => _isLoading;
  String? get phoneNumber => _phoneNumber;
  models.User? get currentUser => _currentUser;

  void _initializeSessionManager() {
    _sessionManager.onSessionExpired = () {
      logout();
      notifyListeners();
    };
  }

  bool _isLocked = false;
  bool get isLocked => _isLocked;

  /// Checks for existing valid session on app start
  Future<void> _checkExistingSession() async {
    try {
      final user = await _appwrite.getCurrentUser();
      if (user != null) {
        _currentUser = user;
        final bioEnabled = await _storage.isBiometricEnabled();

        if (bioEnabled) {
          _isLocked = true;
          _isAuthenticated = false;
        } else {
          _isAuthenticated = true;
        }

        final userRoleStr = await _storage.getUserRole();
        if (userRoleStr != null) {
          _userRole = _parseUserRole(userRoleStr);
        }
        _phoneNumber = await _storage.getPhoneNumber();

        notifyListeners();
      }
    } on Exception catch (e) {
      ErrorHandler.logError(e, context: 'AuthProvider._checkExistingSession');
    }
  }

  /// Unlock app with Biometrics
  Future<bool> unlockApp() async {
    try {
      _isLoading = true;
      notifyListeners();

      final authenticated = await _biometricService.authenticateForLogin();

      if (authenticated) {
        _isLocked = false;
        _isAuthenticated = true;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      _isLoading = false;
      notifyListeners();
      return false;
    } on Exception catch (_) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Send Sign-In Link to Email (OTP)
  Future<bool> sendEmailOTP(String email) async {
    try {
      _isLoading = true;
      notifyListeners();

      final token = await _appwrite.createEmailToken(email: email);
      _emailToken = token.userId;

      _isLoading = false;
      notifyListeners();
      return true;
    } on AppwriteException catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.sendEmailOTP');
      throw AuthException(e.message ?? 'Failed to send email');
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.sendEmailOTP');
      return false;
    }
  }

  /// Sign up with email and password
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? name,
    String? registrationCode,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      // 0. Clear any existing session first to prevent conflicts
      // This is safe even if no session exists - errors are silently ignored
      try {
        await _appwrite.logout();
        developer.log(
          'Cleared existing session before signup',
          name: 'AuthProvider',
        );
      } on Exception {
        // Ignore errors - likely means no session exists, which is fine
        developer.log('No existing session to clear', name: 'AuthProvider');
      }

      // 1. Create Appwrite User
      final user = await _appwrite.createAccount(
        email: email,
        password: password,
        name: name ?? 'User',
      );

      // 2. Create session
      await _appwrite.createEmailPasswordSession(
        email: email,
        password: password,
      );

      // 3. Default role
      const role = UserRole.ewm;

      // 4. Create user document in database
      await _createUserDocument(
        userId: user.$id,
        email: email,
        role: role,
        name: name,
        registrationCode: registrationCode,
      );

      // 5. Start Session
      await _startUserSession(user, role);

      _isLoading = false;
      notifyListeners();
      return true;
    } on AppwriteException catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('SignUp Error: ${e.code} - ${e.message}');
      if (e.code == 409) {
        throw AuthException('Email is already registered. Please login.');
      }
      if (e.code == 401 && e.message?.contains('session') == true) {
        throw AuthException(
          'Session error. Please restart the app and try again.',
        );
      }
      throw AuthException(e.message ?? 'Registration failed');
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.signUpWithEmail');
      throw AuthException('An unexpected error occurred during registration');
    }
  }

  /// Sign in with email and password
  Future<bool> signInWithEmail({
    required String email,
    required String password,
    String? registrationCode,
  }) async {
    String? deviceFingerprint;
    try {
      _isLoading = true;
      notifyListeners();

      // 1. Check rate limiting
      final rateLimitResult = await _rateLimiter.checkLoginAttempt();
      if (!rateLimitResult.allowed) {
        throw AuthException(rateLimitResult.userMessage);
      }

      // 2. Generate device fingerprint for security tracking
      deviceFingerprint = await _fingerprintService.generateFingerprint();
      final deviceName = await _fingerprintService.getDeviceName();

      // 3. SignIn with Appwrite
      await _appwrite.createEmailPasswordSession(
        email: email,
        password: password,
      );

      final user = await _appwrite.getCurrentUser();

      if (user == null) {
        throw AuthException('Login failed');
      }

      _currentUser = user;

      // 4. Fetch User data from database to verify registration code
      final userDoc = await _appwrite.getDocument(
        collectionId: AppwriteService.usersCollectionId,
        documentId: user.$id,
      );

      // 5. Verify registration code if provided
      if (registrationCode != null && registrationCode.isNotEmpty) {
        final storedCode = userDoc.data['registrationCode'] as String?;
        if (storedCode == null || storedCode != registrationCode) {
          // Logout the session since credentials were wrong
          await _appwrite.logout();
          throw AuthException('Invalid registration code');
        }
      }

      // 6. Assess fraud risk
      final fraudAssessment = await _fraudService.assessLoginRisk(
        userId: user.$id,
        deviceFingerprint: deviceFingerprint,
      );

      developer.log(
        'Login fraud assessment: ${fraudAssessment.risk} - ${fraudAssessment.reason}',
        name: 'AuthProvider',
      );

      // 7. Record successful login attempt
      await _fraudService.recordLoginAttempt(
        userId: user.$id,
        success: true,
        deviceFingerprint: deviceFingerprint,
        deviceName: deviceName,
      );

      // 8. Register device as trusted if not already (for new devices)
      if (fraudAssessment.flags.contains('new_device')) {
        await _fraudService.registerTrustedDevice(
          userId: user.$id,
          deviceFingerprint: deviceFingerprint,
          deviceName: deviceName,
        );
      }

      // 9. Get user role
      final roleStr = userDoc.data['role'] as String?;
      final role = _parseUserRole(roleStr) ?? UserRole.ewm;
      _userRole = role;

      // 10. Start user session
      await _startUserSession(user, role);

      // 11. Reset Rate Limiter
      await _rateLimiter.resetLoginAttempts();

      _isLoading = false;
      notifyListeners();
      return true;
    } on AppwriteException catch (e) {
      _isLoading = false;
      notifyListeners();

      // Record failed login attempt
      if (deviceFingerprint != null) {
        try {
          // Note: we don't have user ID for failed login, skip for now
          // Could track by email instead if needed
        } on Exception {
          // Intentionally silent - don't let logging failures block login flow
        }
      }

      developer.log('Login Error: ${e.code} - ${e.message}');
      if (e.code == 401) {
        throw AuthException('Invalid email or password');
      }
      throw AuthException('Login failed. Please check your connection.');
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.signInWithEmail');
      throw AuthException('An unexpected error occurred during login');
    }
  }

  /// Create user document in Appwrite database
  Future<void> _createUserDocument({
    required String userId,
    required String email,
    required UserRole role,
    String? name,
    String? registrationCode,
  }) async {
    await _appwrite.createDocument(
      collectionId: AppwriteService.usersCollectionId,
      documentId: userId,
      data: {
        'email': email,
        'name': name ?? 'User',
        'role': _roleToString(role),
        'registrationCode': registrationCode ?? '',
        'biometricsEnabled': false,
        'createdAt': DateTime.now().toIso8601String(),
        'lastLoginAt': DateTime.now().toIso8601String(),
        'phoneNumber': null,
        'profileImageId': null,
      },
      permissions: [
        'read("user:$userId")', // User can read their own document
        'update("user:$userId")', // User can update their own document
        'delete("user:$userId")', // User can delete their own document
      ],
    );
  }

  /// Start user session and save tokens
  Future<void> _startUserSession(models.User user, UserRole role) async {
    // Appwrite uses session cookies, so we just store user info
    await _storage.saveUserRole(role.name);

    await _sessionManager.startSession(
      authToken: user.$id, // Use user ID as token
      userRole: role.name,
    );

    _isAuthenticated = true;
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
        final authToken = await _storage.getAuthToken();

        if (authToken != null) {
          _isAuthenticated = true;

          final userRoleStr = await _storage.getUserRole();
          _userRole = _parseUserRole(userRoleStr);

          final phoneNumber = await _storage.getPhoneNumber();
          _phoneNumber = phoneNumber;

          await _sessionManager.startSession(
            authToken: authToken,
            userRole: userRoleStr,
          );

          notifyListeners();
          return true;
        } else {
          developer.log(
            'Biometric auth success but no token found',
            name: 'AuthProvider',
          );
          return false;
        }
      }

      return false;
    } on Exception catch (e) {
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
      final canAuthenticate = await _biometricService.authenticate(
        reason: 'Enable biometric login for CRADI Mobile',
      );

      if (canAuthenticate) {
        await _storage.setBiometricEnabled(true);

        // Sync to Appwrite to persist across sessions
        final user = await _appwrite.getCurrentUser();
        if (user != null) {
          try {
            await _appwrite.updateDocument(
              collectionId: AppwriteService.usersCollectionId,
              documentId: user.$id,
              data: {'biometricsEnabled': true},
            );
          } on Exception catch (e) {
            developer.log('Error syncing biometric to Appwrite: $e');
          }
        }
      } else {
        throw AuthException('Biometric authentication failed');
      }
    } else {
      await _storage.setBiometricEnabled(false);

      // Sync to Appwrite
      final user = await _appwrite.getCurrentUser();
      if (user != null) {
        try {
          await _appwrite.updateDocument(
            collectionId: AppwriteService.usersCollectionId,
            documentId: user.$id,
            data: {'biometricsEnabled': false},
          );
        } on Exception catch (e) {
          developer.log('Error syncing biometric to Appwrite: $e');
        }
      }
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
      _isLoading = true;
      notifyListeners();

      await _sessionManager.logout();
      await _appwrite.logout();

      // Clear all secure storage
      await _storage.clearAll(keepPreferences: false);

      // Reset internal state
      _isAuthenticated = false;
      _userRole = null;
      _currentUser = null;
      _phoneNumber = null;
      _emailToken = null;
      _phoneToken = null;

      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.logout');
    }
  }

  /// Parse user role from string
  UserRole? _parseUserRole(String? roleStr) {
    if (roleStr == null) return null;

    try {
      return UserRole.values.firstWhere((role) => role.name == roleStr);
    } on Exception catch (_) {
      return null;
    }
  }

  /// Convert UserRole enum to string
  String _roleToString(UserRole role) {
    return role.name;
  }

  /// Create phone token for OTP
  Future<void> sendPhoneOTP(String phoneNumber) async {
    try {
      _isLoading = true;
      notifyListeners();

      final token = await _appwrite.createPhoneToken(phone: phoneNumber);
      _phoneToken = token.userId;
      _phoneNumber = phoneNumber;

      _isLoading = false;
      notifyListeners();
    } on AppwriteException catch (e) {
      _isLoading = false;
      notifyListeners();
      throw AuthException(e.message ?? 'Failed to send OTP');
    }
  }

  /// Verify email OTP
  Future<bool> verifyEmailOTP(String otp) async {
    try {
      _isLoading = true;
      notifyListeners();

      if (_emailToken == null) {
        throw AuthException('No email verification in progress');
      }

      await _appwrite.verifyEmailOTP(userId: _emailToken!, secret: otp);

      final user = await _appwrite.getCurrentUser();
      if (user == null) {
        throw AuthException('Verification failed');
      }

      _currentUser = user;

      // Check if user document exists or create one (Same logic as phone OTP)
      try {
        final userDoc = await _appwrite.getDocument(
          collectionId: AppwriteService.usersCollectionId,
          documentId: user.$id,
        );

        final roleStr = userDoc.data['role'] as String?;
        _userRole = _parseUserRole(roleStr) ?? UserRole.ewm;
      } on Exception {
        _userRole = UserRole.ewm;
        await _createUserDocument(
          userId: user.$id,
          email: user.email,
          role: _userRole!,
          name: user.name,
        );
      }

      await _startUserSession(user, _userRole!);

      _isAuthenticated = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } on AppwriteException catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.verifyEmailOTP');
      throw AuthException(e.message ?? 'Invalid code');
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.verifyEmailOTP');
      return false;
    }
  }

  /// Verify phone OTP
  Future<bool> verifyPhoneOTP(String otp) async {
    try {
      _isLoading = true;
      notifyListeners();

      if (_phoneToken == null) {
        throw AuthException('No phone verification in progress');
      }

      await _appwrite.createPhoneSession(userId: _phoneToken!, secret: otp);

      final user = await _appwrite.getCurrentUser();
      if (user == null) {
        throw AuthException('Verification failed');
      }

      _currentUser = user;

      // Check if user document exists
      try {
        final userDoc = await _appwrite.getDocument(
          collectionId: AppwriteService.usersCollectionId,
          documentId: user.$id,
        );

        final roleStr = userDoc.data['role'] as String?;
        _userRole = _parseUserRole(roleStr) ?? UserRole.ewm;
      } on Exception {
        // User document doesn't exist, create it
        _userRole = UserRole.ewm;
        await _createUserDocument(
          userId: user.$id,
          email: user.email,
          role: _userRole!,
          name: user.name,
        );
      }

      await _startUserSession(user, _userRole!);

      _isLoading = false;
      notifyListeners();
      return true;
    } on AppwriteException catch (e) {
      _isLoading = false;
      notifyListeners();
      throw AuthException(e.message ?? 'Invalid OTP');
    }
  }

  @override
  void dispose() {
    _sessionManager.dispose();
    super.dispose();
  }
}
