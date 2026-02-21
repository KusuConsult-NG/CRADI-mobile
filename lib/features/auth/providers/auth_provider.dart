import 'dart:developer' as developer;
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/session_manager.dart';
import 'package:climate_app/core/services/rate_limiter.dart';
import 'package:climate_app/core/services/biometric_service.dart';
import 'package:climate_app/core/services/device_fingerprint_service.dart';
import 'package:climate_app/core/services/fraud_detection_service.dart';

import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:climate_app/core/services/sms_service.dart';

enum UserRole { user, ewm, ewv, ewr, admin, techSupport }

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
  String? _phoneNumber;
  bool _isLoading = false;
  models.User? _currentUser;
  bool? _isApproved; // Track admin approval status
  bool _isVerified = false; // Track access code verification status

  // Services
  final SecureStorageService _storage = SecureStorageService();
  final SessionManager _sessionManager = SessionManager();
  final RateLimiter _rateLimiter = RateLimiter();
  final BiometricService _biometricService = BiometricService();
  // Security services
  final DeviceFingerprintService _fingerprintService =
      DeviceFingerprintService();
  final FraudDetectionService _fraudService = FraudDetectionService();

  bool _isInitialized = false; // Flag to indicate initialization complete
  bool _hasCompletedOnboarding = false; // Flag to track onboarding status

  bool get isAuthenticated => _isAuthenticated;
  UserRole? get userRole => _userRole;
  bool get isLoading => _isLoading;
  String? get phoneNumber => _phoneNumber;
  models.User? get currentUser => _currentUser;
  bool? get isApproved => _isApproved; // Getter for approval status
  bool get isVerified => _isVerified; // Getter for verification status
  bool get isInitialized => _isInitialized; // Expose getter
  bool get hasCompletedOnboarding =>
      _hasCompletedOnboarding; // Getter for onboarding status

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
      final prefs = await SharedPreferences.getInstance();
      _hasCompletedOnboarding =
          prefs.getBool('has_completed_onboarding') ?? false;

      final user = await _appwrite.getCurrentUser();
      if (user != null) {
        _currentUser = user;
        final bioEnabled = await _storage.isBiometricEnabled();

        if (bioEnabled) {
          _isLocked = true;
          _isAuthenticated = false;
        } else {
          _isAuthenticated = true;
          // Start session monitoring if authenticated
          _appwrite.startSessionMonitoring();
          developer.log('Session monitoring resumed', name: 'AuthProvider');
        }

        final userRoleStr = await _storage.getUserRole();
        if (userRoleStr != null) {
          _userRole = _parseUserRole(userRoleStr);
        }

        // Fetch latest user data including approval status
        try {
          final userDoc = await _appwrite.getDocument(
            collectionId: AppwriteService.usersCollectionId,
            documentId: user.$id,
          );
          _isApproved = userDoc.data['isApproved'] as bool? ?? false;
          _isVerified = userDoc.data['isVerified'] as bool? ?? false;

          // SELF-HEALING: If Auth is verified but DB is not, update DB
          if (user.emailVerification && !_isVerified) {
            developer.log(
              'Auth verified but DB not. Syncing...',
              name: 'AuthProvider',
            );
            try {
              await _appwrite.updateDocument(
                collectionId: AppwriteService.usersCollectionId,
                documentId: user.$id,
                data: {'isVerified': true},
              );
              _isVerified = true;
            } on Exception catch (e) {
              developer.log('Failed to sync verification: $e');
            }
          }
        } on Exception catch (e) {
          developer.log('Error fetching approval status: $e');
        }
        _phoneNumber = await _storage.getPhoneNumber();
      }
    } on Exception catch (e) {
      ErrorHandler.logError(e, context: 'AuthProvider.checkSession');
      _currentUser = null;
      _userRole = null;
    } finally {
      // Mark initialization as complete regardless of outcome
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_completed_onboarding', true);
    _hasCompletedOnboarding = true;
    notifyListeners();
  }

  /// Public method to force reload of user data
  Future<void> reloadUserData() async {
    await _checkExistingSession();
  }

  /// Unlock app with Biometrics
  Future<bool> unlockApp() async {
    try {
      _isLoading = true;
      notifyListeners();

      final authenticated = await _biometricService.authenticateForLogin();

      if (authenticated) {
        // Validate against backend explicitly to prevent immortal tokens
        final isValid = await _isServerSessionValid();
        if (!isValid) {
          _isLoading = false;
          _isLocked = false;
          notifyListeners();
          return false;
        }

        _isLocked = false;
        _isAuthenticated = true;

        // Start session monitoring after biometric unlock
        _appwrite.startSessionMonitoring();
        developer.log(
          'Session monitoring started after biometric unlock',
          name: 'AuthProvider',
        );

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

  /// Sign up with email and password
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? name,
    String? address,
    UserRole? role, // Default to UserRole.user if not provided
    String? state, // Added state
    String? lga, // Added lga
    String? ward, // Added ward
    bool? isVerified, // Added pre-verification status
    String? phoneNumber, // Added phoneNumber
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      // 0. Clear any existing session first to prevent conflicts
      try {
        await _appwrite.logout();
        developer.log(
          'Cleared existing session before signup',
          name: 'AuthProvider',
        );
      } on Exception {
        // Ignore errors - likely means no session exists
        developer.log('No existing session to clear', name: 'AuthProvider');
      }

      // 1. Create Appwrite User
      developer.log('Creating Appwrite account...', name: 'AuthProvider');
      final user = await _appwrite.createAccount(
        email: email,
        password: password,
        name: name ?? 'User',
      );
      developer.log('Account created: ${user.$id}', name: 'AuthProvider');
      _currentUser = user; // Fix: Set current user immediately

      // 2. Create session
      developer.log('Creating session...', name: 'AuthProvider');
      await _appwrite.createEmailPasswordSession(
        email: email,
        password: password,
      );
      developer.log('Session created', name: 'AuthProvider');

      // 3. Use provided role
      final userRole = role ?? UserRole.user;

      // 4. Generate Access Code (Deprecated, replaced by Verification Link)
      developer.log(
        'Skipping OTP Access Code generation - using links',
        name: 'AuthProvider',
      );
      const accessCode = '';

      // 5. Create user document in database
      developer.log('Creating user document...', name: 'AuthProvider');
      await _createUserDocument(
        userId: user.$id,
        email: email,
        role: userRole,
        name: name,
        address: address,
        state: state,
        lga: lga,
        ward: ward,
        isVerified: isVerified ?? false, // User is verified if pre-check passed
        accessCode: accessCode, // Deprecated, using links now
        phoneNumber: phoneNumber,
      );
      developer.log('User document created', name: 'AuthProvider');

      // 6. Start Session
      developer.log('Starting user session...', name: 'AuthProvider');
      try {
        await _startUserSession(
          user,
          userRole,
          isVerified: isVerified ?? false,
        );
        developer.log('User session started', name: 'AuthProvider');

        // 7. Send Verification Link if not pre-verified
        if (isVerified != true) {
          await _appwrite.createVerification();
          developer.log('Verification link sent to user', name: 'AuthProvider');
        }
      } on Exception catch (e) {
        developer.log(
          'Session setup warning: $e (non-critical)',
          name: 'AuthProvider',
        );
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } on AppwriteException catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log(
        'SignUp AppwriteException: ${e.code} - ${e.message}',
        name: 'AuthProvider',
      );
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
      developer.log('SignUp General Exception: $e', name: 'AuthProvider');
      ErrorHandler.logError(e, context: 'AuthProvider.signUpWithEmail');
      // Show more specific error to help debugging
      final errorMsg = e.toString();
      if (errorMsg.contains('Document') ||
          errorMsg.contains('Invalid document structure')) {
        developer.log('Schema Error: $errorMsg', name: 'AuthProvider');
        throw AuthException(
          'Registration failed: Database schema mismatch. Please contact support.',
        );
      } else if (errorMsg.contains('network') ||
          errorMsg.contains('connection')) {
        throw AuthException('Network error. Please check your connection.');
      }
      throw AuthException(
        'Registration error: ${errorMsg.length > 100 ? errorMsg.substring(0, 100) : errorMsg}',
      );
    }
  }

  /// Sign in with email and password
  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    String? deviceFingerprint;
    try {
      _isLoading = true;
      notifyListeners();

      // 0. Clear any existing session first to prevent 401 "session already active" error
      try {
        await _appwrite.logout();
        developer.log(
          'Cleared existing session before login',
          name: 'AuthProvider',
        );
      } on Exception {
        // Ignore errors - likely means no session exists, which is fine
        developer.log('No existing session to clear', name: 'AuthProvider');
      }

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

      // 4. Fetch User data from database
      models.Document userDoc;
      try {
        userDoc = await _appwrite.getDocument(
          collectionId: AppwriteService.usersCollectionId,
          documentId: user.$id,
        );
      } on AppwriteException catch (e) {
        if (e.code == 404) {
          developer.log(
            'User document missing (Zombie User), attempting recovery...',
            name: 'AuthProvider',
          );
          // Recovery: Create missing document
          await _createUserDocument(
            userId: user.$id,
            email: user.email,
            name: user.name,
            role: UserRole.user, // Default role for recovered users
          );
          // Fetch again
          userDoc = await _appwrite.getDocument(
            collectionId: AppwriteService.usersCollectionId,
            documentId: user.$id,
          );
        } else {
          rethrow;
        }
      }

      // 5. Validate user document fields
      final requiredFields = ['email', 'name', 'role', 'address'];
      final missingFields = requiredFields
          .where((field) => !userDoc.data.containsKey(field))
          .toList();

      if (missingFields.isNotEmpty) {
        developer.log(
          'CRITICAL: Missing fields in user document: $missingFields',
          name: 'AuthProvider',
        );
        // Attempt partial recovery if possible or just proceed with defaults to avoid blocking
        // For now, we allow it but log it, as blocking prevents app usage
      }

      // 6. Get user role
      final roleStr = userDoc.data['role'] as String?;
      final role = _parseUserRole(roleStr) ?? UserRole.user;
      _userRole = role;

      // 6.5. Get approval and verification status
      final isApproved = userDoc.data['isApproved'] as bool? ?? false;
      _isApproved = isApproved;

      final isVerified = userDoc.data['isVerified'] as bool? ?? false;
      _isVerified = isVerified;

      // 7. Assess fraud risk (non-critical - don't block login if this fails)
      try {
        final fraudAssessment = await _fraudService.assessLoginRisk(
          userId: user.$id,
          deviceFingerprint: deviceFingerprint,
        );

        developer.log(
          'Login fraud assessment: ${fraudAssessment.risk} - ${fraudAssessment.reason}',
          name: 'AuthProvider',
        );

        // Record successful login attempt
        await _fraudService.recordLoginAttempt(
          userId: user.$id,
          success: true,
          deviceFingerprint: deviceFingerprint,
          deviceName: deviceName,
        );

        // Register device as trusted if not already (for new devices)
        if (fraudAssessment.flags.contains('new_device')) {
          await _fraudService.registerTrustedDevice(
            userId: user.$id,
            deviceFingerprint: deviceFingerprint,
            deviceName: deviceName,
          );
        }
      } on Exception catch (e) {
        // Non-critical - log but don't  block login
        developer.log(
          'Fraud detection warning: $e (non-critical)',
          name: 'AuthProvider',
        );
      }

      // 8. Start user session
      await _startUserSession(user, role);

      // 9. Start automatic session monitoring for token refresh
      _appwrite.startSessionMonitoring();
      developer.log('Session monitoring started', name: 'AuthProvider');

      // 10. Reset Rate Limiter
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

  /// Send an OTP to a phone number
  Future<bool> sendOtpForPhone(String phone) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Check rate limit
      final rateLimitResult = await _rateLimiter.checkLoginAttempt();
      if (!rateLimitResult.allowed) {
        throw AuthException(rateLimitResult.userMessage);
      }

      // Generate 6-digit OTP
      final rnd = Random.secure();
      String otp = (rnd.nextInt(900000) + 100000)
          .toString(); // 100000 to 999999

      if (!SmsService().isReady) {
        developer.log(
          'SMS Service is not configured or ready. Cannot send OTP.',
          name: 'AuthProvider',
        );
        throw AuthException(
          'SMS service is currently unavailable. Please try again later.',
        );
      }

      // Hash it
      final bytes = utf8.encode(otp);
      final hash = sha256.convert(bytes).toString();

      // Store temporarily (10 mins expiry)
      final expiry = DateTime.now().add(const Duration(minutes: 10));
      await _storage.saveOtpData(hash: hash, expiry: expiry, phone: phone);

      // Send via SmsService
      String? msgId = await SmsService().sendOtp(to: phone, otp: otp);

      if (msgId == null) {
        throw AuthException(
          'Failed to send SMS. Please check your network or try again.',
        );
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException {
      rethrow;
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Send OTP Error: $e', name: 'AuthProvider');
      throw AuthException('An error occurred while sending OTP: $e');
    }
  }

  /// Verify OTP and login (or register if not exists)
  Future<bool> verifyOtpAndLogin(
    String otp, {
    Map<String, dynamic>? registrationData,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      final otpData = await _storage.getOtpData();
      final storedHash = otpData['hash'];
      final storedExpiryStr = otpData['expiry'];
      final storedPhone = otpData['phone'];

      if (storedHash == null ||
          storedExpiryStr == null ||
          storedPhone == null) {
        throw AuthException('OTP session expired. Please request a new code.');
      }

      final expiry = DateTime.parse(storedExpiryStr);
      if (DateTime.now().isAfter(expiry)) {
        await _storage.clearOtpData();
        throw AuthException('OTP has expired. Please request a new code.');
      }

      // Verify hash
      final bytes = utf8.encode(otp);
      final hash = sha256.convert(bytes).toString();

      if (hash != storedHash) {
        throw AuthException('Invalid OTP. Please try again.');
      }

      // OTP is valid.
      // Scenario A: User is already logged in (they just registered). We just verify their account.
      if (_currentUser != null) {
        try {
          await _appwrite.updateDocument(
            collectionId: AppwriteService.usersCollectionId,
            documentId: _currentUser!.$id,
            data: {'isVerified': true},
          );
          _isVerified = true;
          await _storage.clearOtpData();
          _isLoading = false;
          notifyListeners();
          return true;
        } on Exception catch (_) {
          throw AuthException(
            'Failed to update verification status in database.',
          );
        }
      }

      // Scenario B: User is NOT logged in. We authenticate with Appwrite via mapped email
      final cleanPhone = storedPhone.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanPhone.isEmpty) {
        throw AuthException('Invalid phone format stored.');
      }

      final mappedEmail = '$cleanPhone@cradi.local';
      final mappedPassword = 'cradi_$cleanPhone!0';

      // Check if user exists by trying to login directly
      try {
        await signInWithEmail(email: mappedEmail, password: mappedPassword);
      } on AuthException catch (e) {
        if (e.userMessage.contains('Invalid email or password') ||
            e.userMessage.contains('Login failed')) {
          // User doesn't exist, register them
          await signUpWithEmail(
            email: mappedEmail,
            password: mappedPassword,
            name: registrationData?['name'] ?? 'User ($storedPhone)',
            phoneNumber: storedPhone,
            isVerified: true,
            address: registrationData?['address'] ?? 'No Address Provided',
            role: registrationData?['role'] ?? UserRole.user,
            state: registrationData?['state'],
            lga: registrationData?['lga'],
            ward: registrationData?['ward'],
          );
        } else {
          rethrow;
        }
      }

      // Login successful, clean up
      await _storage.clearOtpData();

      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException {
      _isLoading = false;
      notifyListeners();
      rethrow;
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Verify OTP Error: $e', name: 'AuthProvider');
      throw AuthException('An error occurred during verification.');
    }
  }

  // verifyAccount was removed. Authentication uses verification links now.

  /// Resend verification link to user's email
  Future<void> resendVerificationLink() async {
    try {
      // Robustness: Recover user if null
      if (_currentUser == null) {
        developer.log(
          'User null in resend, attempting recovery...',
          name: 'AuthProvider',
        );
        final user = await _appwrite.getCurrentUser();
        if (user != null) {
          _currentUser = user;
        } else {
          throw AuthException('User not logged in');
        }
      }

      _isLoading = true;
      notifyListeners();

      // Send Verification Link using native Appwrite
      developer.log('Resending verification link...', name: 'AuthProvider');
      await _appwrite.createVerification();
      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Resend Code Error: $e', name: 'AuthProvider');
      throw AuthException('Failed to resend code. Please try again.');
    }
  }

  /// Verify email from the magic link
  Future<void> verifyEmail(String userId, String secret) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Submit verification token to Appwrite Account API
      await _appwrite.updateVerification(userId: userId, secret: secret);

      // Successfully verified. Update local state
      _isVerified = true;

      // Update the user document explicitly to sync verification status
      try {
        await _appwrite.updateDocument(
          collectionId: AppwriteService.usersCollectionId,
          documentId: userId,
          data: {'isVerified': true},
        );
      } on Exception catch (docError) {
        developer.log(
          'Warning: Failed to update user document to verified state: $docError',
          name: 'AuthProvider',
        );
        // Non-critical, token was verified.
      }

      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Email verification failed: $e', name: 'AuthProvider');
      throw AuthException(
        'Verification failed. The link may have expired or is invalid.',
      );
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _appwrite.createRecovery(email: email);

      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Password reset error: $e', name: 'AuthProvider');
      ErrorHandler.logError(e, context: 'AuthProvider.sendPasswordResetEmail');
      throw AuthException('Failed to send reset email. Please try again.');
    }
  }

  /// Execute password reset using secret from email link
  Future<void> resetPassword({
    required String userId,
    required String secret,
    required String password,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _appwrite.resetPassword(
        userId: userId,
        secret: secret,
        password: password,
      );

      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Execute reset password error: $e', name: 'AuthProvider');
      ErrorHandler.logError(e, context: 'AuthProvider.resetPassword');
      throw AuthException(
        'Failed to reset password. Link might be invalid or expired.',
      );
    }
  }

  /// Create user document in Appwrite database
  Future<void> _createUserDocument({
    required String userId,
    required String email,
    required UserRole role,
    String? name,
    String? address,
    String? state,
    String? lga,
    String? ward,
    bool isVerified = false,
    String? accessCode,
    String? phoneNumber,
  }) async {
    await _appwrite.createDocument(
      collectionId: AppwriteService.usersCollectionId,
      documentId: userId,
      data: {
        'email': email,
        'name': name ?? 'User',
        'role': _roleToString(role),
        'address': address ?? '',
        'state': state ?? '',
        'lga': lga ?? '',
        'ward': ward ?? '',
        'isVerified': isVerified,
        // Restored schema fields as requested
        'biometricsEnabled': false,
        'createdAt': DateTime.now().toIso8601String(),
        'lastLoginAt': DateTime.now().toIso8601String(),
        'phone': phoneNumber,
        'profileImageId':
            null, // Changed back to profileImageId to match actual schema
      },
      // Permissions are managed at collection level in Appwrite console
    );
  }

  /// Start user session and save tokens
  Future<void> _startUserSession(
    models.User user,
    UserRole role, {
    bool isVerified = true,
  }) async {
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
        // Validate against backend explicitly to prevent immortal tokens
        final isValid = await _isServerSessionValid();
        if (!isValid) {
          return false; // Will prompt for password since token is explicitly dead
        }

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

  /// Validate current session with server
  ///
  /// This method proactively validates the Appwrite session and extends
  /// the client-side timeout if valid. Returns true if session is valid.
  Future<bool> validateSession() async {
    return await _isServerSessionValid();
  }

  /// Explicitly check server session to prevent immortal biometric tokens
  /// If it receives a 401/403, logs out the user.
  /// If there's a network error, assumes valid to allow offline usage.
  Future<bool> _isServerSessionValid() async {
    try {
      // Use raw client to properly catch the AppwriteException,
      // since AppwriteService.getCurrentUser() catches and returns null
      final account = Account(_appwrite.appwriteClient);
      await account.get();

      // Session is valid - extend client timeout
      await _sessionManager.extendSession();
      developer.log('Session validated and extended', name: 'AuthProvider');
      return true;
    } on AppwriteException catch (e) {
      if (e.code == 401 || e.code == 403) {
        developer.log(
          'Session explicitly expired on server',
          name: 'AuthProvider',
        );
        await logout();
        return false;
      }
      // Network error or other - assume valid to allow offline access
      developer.log('Session network warning: $e', name: 'AuthProvider');
      return true;
    } on Exception catch (e) {
      // Network error - assume valid to allow offline access
      developer.log('Session network error: $e', name: 'AuthProvider');
      return true;
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

      try {
        await _sessionManager.logout();
      } on Exception catch (e) {
        developer.log('Session manager logout error: $e', name: 'AuthProvider');
      }

      try {
        await _appwrite.logout();
      } on Exception catch (e) {
        developer.log('Appwrite logout error: $e', name: 'AuthProvider');
        // Continue logout process even if remote session invalid
      }

      // Clear all secure storage
      await _storage.clearAll(keepPreferences: false);

      // Reset internal state
      _isAuthenticated = false;
      _userRole = null;
      _currentUser = null;
      _phoneNumber = null;

      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      // Even if main block fails, ensure we reset state as fallback
      _isAuthenticated = false;
      _userRole = null;
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

  @override
  void dispose() {
    _sessionManager.dispose();
    super.dispose();
  }
}
