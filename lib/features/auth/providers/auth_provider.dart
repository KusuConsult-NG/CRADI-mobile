import 'dart:developer' as developer;
import 'package:climate_app/core/utils/error_handler.dart';
export 'package:climate_app/core/utils/error_handler.dart' show AuthException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:climate_app/core/services/firebase_service.dart';
import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/session_manager.dart';
import 'package:climate_app/core/services/rate_limiter.dart';
import 'package:climate_app/core/services/biometric_service.dart';
import 'package:climate_app/core/services/device_fingerprint_service.dart';
import 'package:climate_app/core/services/fraud_detection_service.dart';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:climate_app/core/services/email_service.dart';
import 'package:climate_app/core/constants/app_config.dart';

import 'package:flutter/material.dart';

enum UserRole { user, ewm, ewv, ewr, admin, techSupport }

/// Authentication state and operations — backed by Firebase Auth + Firestore.
///
/// Session management moved from Appwrite cookie sessions to Firebase's
/// built-in [authStateChanges] stream. JWT refresh is automatic.
class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    _initializeSessionManager();
    // Access _authSub here to force initialization of the late field,
    // which starts listening to Firebase authStateChanges immediately.
    // ignore: unnecessary_statements
    _authSub;
  }

  final FirebaseService _firebase = FirebaseService();
  bool _isAuthenticated = false;
  UserRole? _userRole;
  String? _phoneNumber;
  bool _isLoading = false;
  User? _currentUser;
  bool? _isApproved;
  bool _isVerified = false;

  // Services
  final SecureStorageService _storage = SecureStorageService();
  final SessionManager _sessionManager = SessionManager();
  final RateLimiter _rateLimiter = RateLimiter();
  final BiometricService _biometricService = BiometricService();
  final DeviceFingerprintService _fingerprintService =
      DeviceFingerprintService();
  final FraudDetectionService _fraudService = FraudDetectionService();

  bool _isInitialized = false;
  bool _hasCompletedOnboarding = false;
  bool _isLocked = false;

  // Auth state subscription (initialized in constructor indirectly via late field).
  // This is safe: late fields are initialized on first access, which happens
  // immediately when the listener is needed.
  // ignore: cancel_subscriptions
  late final _authSub = _firebase.authStateChanges.listen(_onAuthStateChanged);

  bool get isAuthenticated => _isAuthenticated;
  UserRole? get userRole => _userRole;
  bool get isLoading => _isLoading;
  String? get phoneNumber => _phoneNumber;
  User? get currentUser => _currentUser;
  bool? get isApproved => _isApproved;
  bool get isVerified => _isVerified;
  bool get isInitialized => _isInitialized;
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;
  bool get isLocked => _isLocked;

  // ─────────────────────────── Initialization ───────────────────────────────

  void _initializeSessionManager() {
    _sessionManager.onSessionExpired = () {
      logout();
      notifyListeners();
    };
  }

  /// React to Firebase auth state changes (replaces 2-min polling timer).
  Future<void> _onAuthStateChanged(User? user) async {
    if (user == null) {
      // Signed out
      _currentUser = null;
      _isAuthenticated = false;
      _userRole = null;
      _isInitialized = true;
      notifyListeners();
      return;
    }

    _currentUser = user;

    // Load onboarding status
    final prefs = await SharedPreferences.getInstance();
    _hasCompletedOnboarding =
        prefs.getBool('has_completed_onboarding') ?? false;

    // Check biometric lock
    final bioEnabled = await _storage.isBiometricEnabled();
    if (bioEnabled) {
      _isLocked = true;
      _isAuthenticated = false;
    } else {
      _isAuthenticated = true;
    }

    // Load role from secure storage (fast path)
    final userRoleStr = await _storage.getUserRole();
    if (userRoleStr != null) {
      _userRole = _parseUserRole(userRoleStr);
    }

    // Fetch Firestore user doc for approval/verification status
    try {
      final userDoc = await _firebase.getDocument(
        collectionId: AppConfig.usersCollection,
        documentId: user.uid,
      );
      _isApproved = userDoc['isApproved'] as bool? ?? false;
      _isVerified = userDoc['isVerified'] as bool? ?? false;

      // Self-heal: if Firebase email is verified but Firestore is not
      if (user.emailVerified && !_isVerified) {
        developer.log(
          'Auth verified but Firestore not. Syncing...',
          name: 'AuthProvider',
        );
        try {
          await _firebase.updateDocument(
            collectionId: AppConfig.usersCollection,
            documentId: user.uid,
            data: {'isVerified': true},
          );
          _isVerified = true;
        } on Exception catch (e) {
          developer.log('Failed to sync verification: $e');
        }
      }
    } on Exception catch (e) {
      developer.log('Error fetching Firestore user doc: $e');
    }

    _phoneNumber = await _storage.getPhoneNumber();
    _isInitialized = true;
    notifyListeners();
  }

  /// Force reload of user data (e.g. after profile update).
  Future<void> reloadUserData() async {
    await _firebase.reloadCurrentUser();
    final user = _firebase.getCurrentUser();
    if (user != null) await _onAuthStateChanged(user);
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_completed_onboarding', true);
    _hasCompletedOnboarding = true;
    notifyListeners();
  }

  // ─────────────────────────── Biometric Lock ───────────────────────────────

  Future<bool> unlockApp() async {
    try {
      _isLoading = true;
      notifyListeners();

      final authenticated = await _biometricService.authenticateForLogin();

      if (authenticated) {
        // Validate server session
        final isValid = await _isServerSessionValid();
        if (!isValid) {
          _isLoading = false;
          _isLocked = false;
          notifyListeners();
          return false;
        }

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

  // ─────────────────────────── Sign Up ─────────────────────────────────────

  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? name,
    String? address,
    UserRole? role,
    String? state,
    String? lga,
    String? ward,
    bool? isVerified,
    String? phoneNumber,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Sign out any stale session
      try {
        await _firebase.logout();
      } on Exception {
        developer.log('No existing session to clear', name: 'AuthProvider');
      }

      // 1. Create Firebase Auth user
      developer.log('Creating Firebase account...', name: 'AuthProvider');
      final user = await _firebase.createAccount(
        email: email,
        password: password,
        name: name ?? 'User',
      );
      developer.log('Account created: ${user.uid}', name: 'AuthProvider');
      _currentUser = user;

      // 2. Determine role
      final userRole = role ?? UserRole.user;

      // 3. Skip OTP Generation since email verification is handled via Action Links directly if needed

      // 4. Create Firestore user document
      developer.log(
        'Creating Firestore user document...',
        name: 'AuthProvider',
      );
      await _createUserDocument(
        userId: user.uid,
        email: email,
        role: userRole,
        name: name,
        address: address,
        state: state,
        lga: lga,
        ward: ward,
        isVerified: isVerified ?? false,
        phoneNumber: phoneNumber,
      );
      developer.log('User document created', name: 'AuthProvider');

      // 5. Start session
      await _startUserSession(user, userRole, isVerified: isVerified ?? false);

      // 6. Send OTP email (legacy method no longer functional without proper flow, stub it out)
      if (isVerified != true) {
        developer.log(
          'Email verification required, but OTP bypass is active.',
          name: 'AuthProvider',
        );
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log(
        'SignUp FirebaseAuthException: ${e.code} – ${e.message}',
        name: 'AuthProvider',
      );
      if (e.code == 'email-already-in-use') {
        throw AuthException('Email is already registered. Please login.');
      }
      throw AuthException(e.message ?? 'Registration failed');
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.signUpWithEmail');
      final errorMsg = e.toString();
      if (errorMsg.contains('network') || errorMsg.contains('connection')) {
        throw AuthException('Network error. Please check your connection.');
      }
      throw AuthException(
        'Registration error: ${errorMsg.length > 100 ? errorMsg.substring(0, 100) : errorMsg}',
      );
    }
  }

  // ─────────────────────────── Sign In ─────────────────────────────────────

  Future<bool> signInWithEmail({
    required String email,
    required String password,
  }) async {
    String? deviceFingerprint;
    try {
      _isLoading = true;
      notifyListeners();

      // Clear stale state
      try {
        await _firebase.logout();
      } on Exception {
        developer.log('No existing session to clear', name: 'AuthProvider');
      }
      _currentUser = null;
      _isAuthenticated = false;
      _userRole = null;

      // Rate limit check
      final rateLimitResult = await _rateLimiter.checkLoginAttempt();
      if (!rateLimitResult.allowed) {
        throw AuthException(rateLimitResult.userMessage);
      }

      // Device fingerprint for fraud tracking
      deviceFingerprint = await _fingerprintService.generateFingerprint();
      final deviceName = await _fingerprintService.getDeviceName();

      // Sign in with Firebase
      final user = await _firebase.createEmailPasswordSession(
        email: email,
        password: password,
      );
      _currentUser = user;

      // Fetch Firestore user document
      Map<String, dynamic> userDoc;
      try {
        userDoc = await _firebase.getDocument(
          collectionId: AppConfig.usersCollection,
          documentId: user.uid,
        );
      } on FirebaseException catch (e) {
        if (e.code == 'not-found') {
          developer.log(
            'User document missing (Zombie User), recovering...',
            name: 'AuthProvider',
          );
          await _createUserDocument(
            userId: user.uid,
            email: user.email ?? email,
            name: user.displayName,
            role: UserRole.user,
          );
          userDoc = await _firebase.getDocument(
            collectionId: AppConfig.usersCollection,
            documentId: user.uid,
          );
        } else {
          rethrow;
        }
      }

      final roleStr = userDoc['role'] as String?;
      final role = _parseUserRole(roleStr) ?? UserRole.user;
      _userRole = role;
      _isApproved = userDoc['isApproved'] as bool? ?? false;
      _isVerified = userDoc['isVerified'] as bool? ?? false;

      // Fraud assessment (non-blocking)
      try {
        final fraudAssessment = await _fraudService.assessLoginRisk(
          userId: user.uid,
          deviceFingerprint: deviceFingerprint,
        );
        developer.log(
          'Fraud assessment: ${fraudAssessment.risk} – ${fraudAssessment.reason}',
          name: 'AuthProvider',
        );

        await _fraudService.recordLoginAttempt(
          userId: user.uid,
          success: true,
          deviceFingerprint: deviceFingerprint,
          deviceName: deviceName,
        );

        if (fraudAssessment.flags.contains('new_device')) {
          await _fraudService.registerTrustedDevice(
            userId: user.uid,
            deviceFingerprint: deviceFingerprint,
            deviceName: deviceName,
          );
        }
      } on Exception catch (e) {
        developer.log(
          'Fraud detection warning: $e (non-critical)',
          name: 'AuthProvider',
        );
      }

      await _startUserSession(user, role);
      await _rateLimiter.resetLoginAttempts();

      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Login error: ${e.code} – ${e.message}');
      if (e.code == 'invalid-credential' ||
          e.code == 'wrong-password' ||
          e.code == 'user-not-found') {
        throw AuthException('Invalid email or password');
      }
      if (e.code == 'rate-limited') {
        throw AuthException(e.message ?? 'Too many attempts');
      }
      throw AuthException('Login failed. Please check your connection.');
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.signInWithEmail');
      throw AuthException('An unexpected error occurred during login');
    }
  }

  // ─────────────────────────── OTP ─────────────────────────────────────────

  Future<bool> sendOtpForPhone(String phone) async {
    throw AuthException('Phone OTP is disabled.');
  }

  Future<bool> sendOtpForEmail(String email, {String? name}) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Implement rate limiting
      final rateLimitResult = await _rateLimiter.checkOtpResend();
      if (!rateLimitResult.allowed) {
        throw AuthException(rateLimitResult.userMessage);
      }

      // Generate a cryptographically secure 6-digit OTP
      final secureRandom = math.Random.secure();
      final otp = (100000 + secureRandom.nextInt(900000)).toString();

      // Save it to Firestore
      final expiryTime = DateTime.now().add(const Duration(minutes: 10));
      await FirebaseFirestore.instance
          .collection('otp_verifications')
          .doc(email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_'))
          .set({
            'email': email,
            'code': otp,
            'expiresAt': Timestamp.fromDate(expiryTime),
            'createdAt': FieldValue.serverTimestamp(),
            'used': false,
          });

      // Send the OTP via EmailService (Resend)
      final emailService = EmailService();
      final success = await emailService.sendVerificationCode(
        email,
        otp,
        name: name,
      );

      if (!success) {
        throw AuthException(
          'Failed to send verification email. Please try again.',
        );
      }

      await _rateLimiter.recordOtpResend();

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
      ErrorHandler.logError(e, context: 'AuthProvider.sendOtpForEmail');
      throw AuthException('Failed to send verification code.');
    }
  }

  Future<bool> verifyOtpAndLogin(
    String otp, {
    Map<String, dynamic>? registrationData,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      if (registrationData == null || !registrationData.containsKey('email')) {
        // Fallback for an existing user logging in or verifying without full registration data
        final user = _firebase.getCurrentUser();
        if (user == null) {
          throw AuthException('No user context for verification.');
        }
        registrationData = {'email': user.email};
      }

      final email = registrationData['email'] as String;
      final docId = email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      try {
        await FirebaseFirestore.instance
            .collection('otp_verifications')
            .doc(docId)
            .update({'verifyCode': otp, 'used': true});

        // Verification successful, update the user in Firestore if they are logged in
        final user = _firebase.getCurrentUser();
        if (user != null) {
          await _firebase.updateDocument(
            collectionId: AppConfig.usersCollection,
            documentId: user.uid,
            data: {'isVerified': true},
          );
          _isVerified = true;
        }

        _isLoading = false;
        notifyListeners();
        return true;
      } on FirebaseException catch (e) {
        if (e.code == 'not-found') {
          throw AuthException('Invalid or expired verification code.');
        }
        if (e.code == 'permission-denied') {
          throw AuthException(
            'Invalid or expired verification code. Please request a new one.',
          );
        }
        rethrow;
      }
    } on AuthException {
      _isLoading = false;
      notifyListeners();
      rethrow;
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.verifyOtpAndLogin');
      throw AuthException('Failed to verify code.');
    }
  }

  Future<void> resendVerificationLink() async {
    try {
      if (_currentUser == null) {
        final user = _firebase.getCurrentUser();
        if (user != null) {
          _currentUser = user;
        } else {
          throw AuthException('User not logged in');
        }
      }

      await sendOtpForEmail(
        _currentUser!.email!,
        name: _currentUser!.displayName,
      );
    } on Exception catch (e) {
      throw AuthException('Failed to resend code: $e');
    }
  }

  // ─────────────────────────── Password Reset ───────────────────────────────

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      _isLoading = true;
      notifyListeners();
      await _firebase.createRecovery(email: email);
      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.sendPasswordResetEmail');
      throw AuthException('Failed to send reset email. Please try again.');
    }
  }

  // ─────────────────────────── Biometrics ──────────────────────────────────

  Future<bool> authenticateWithBiometrics() async {
    try {
      final isBiometricEnabled = await _storage.isBiometricEnabled();
      if (!isBiometricEnabled) return false;

      final authenticated = await _biometricService.authenticateForLogin();
      if (authenticated) {
        final isValid = await _isServerSessionValid();
        if (!isValid) return false;

        _isAuthenticated = true;
        final userRoleStr = await _storage.getUserRole();
        _userRole = _parseUserRole(userRoleStr);
        _phoneNumber = await _storage.getPhoneNumber();
        notifyListeners();
        return true;
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

  Future<void> setBiometricEnabled(bool enabled) async {
    if (enabled) {
      final canAuth = await _biometricService.authenticate(
        reason: 'Enable biometric login for EWER',
      );
      if (canAuth) {
        await _storage.setBiometricEnabled(true);
        final user = _firebase.getCurrentUser();
        if (user != null) {
          try {
            await _firebase.updateDocument(
              collectionId: AppConfig.usersCollection,
              documentId: user.uid,
              data: {'biometricsEnabled': true},
            );
          } on Exception catch (e) {
            developer.log('Error syncing biometric to Firestore: $e');
          }
        }
      } else {
        throw AuthException('Biometric authentication failed');
      }
    } else {
      await _storage.setBiometricEnabled(false);
      final user = _firebase.getCurrentUser();
      if (user != null) {
        try {
          await _firebase.updateDocument(
            collectionId: AppConfig.usersCollection,
            documentId: user.uid,
            data: {'biometricsEnabled': false},
          );
        } on Exception catch (e) {
          developer.log('Error syncing biometric to Firestore: $e');
        }
      }
    }
    notifyListeners();
  }

  Future<bool> isBiometricEnabled() => _storage.isBiometricEnabled();
  Future<bool> isBiometricAvailable() =>
      _biometricService.isBiometricAvailable();

  // ─────────────────────────── Session ─────────────────────────────────────

  void recordActivity() {
    if (_isAuthenticated) _sessionManager.recordActivity();
  }

  Future<bool> validateSession() => _isServerSessionValid();

  Future<bool> _isServerSessionValid() async {
    try {
      // Firebase tokens auto-refresh; a reload confirms validity
      await _firebase.reloadCurrentUser();
      await _sessionManager.extendSession();
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-token-expired' || e.code == 'user-not-found') {
        developer.log('Session expired: ${e.code}', name: 'AuthProvider');
        await logout();
        return false;
      }
      // Network issues — allow offline access
      return true;
    } on Exception catch (e) {
      developer.log('Session network error: $e', name: 'AuthProvider');
      return true;
    }
  }

  Future<Duration?> getSessionTimeRemaining() =>
      _sessionManager.getRemainingTime();

  // ─────────────────────────── Logout ──────────────────────────────────────

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
        await _firebase.logout();
      } on Exception catch (e) {
        developer.log('Firebase logout error: $e', name: 'AuthProvider');
      }

      await _storage.clearAll(keepPreferences: false);

      _isAuthenticated = false;
      _userRole = null;
      _currentUser = null;
      _phoneNumber = null;
      _isApproved = null;
      _isVerified = false;
      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _isAuthenticated = false;
      _userRole = null;
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.logout');
    }
  }

  // ─────────────────────────── Helpers ─────────────────────────────────────

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
    String? phoneNumber,
  }) async {
    await _firebase.createDocument(
      collectionId: AppConfig.usersCollection,
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
        'isApproved': false,
        'biometricsEnabled': false,
        'createdAt': DateTime.now().toIso8601String(),
        'lastLoginAt': DateTime.now().toIso8601String(),
        'phone': phoneNumber ?? '',
        'profileImageUrl': '',
      },
    );
  }

  Future<void> _startUserSession(
    User user,
    UserRole role, {
    bool isVerified = true,
  }) async {
    await _storage.saveUserRole(role.name);
    await _sessionManager.startSession(
      authToken: user.uid,
      userRole: role.name,
    );
    _isAuthenticated = true;
  }

  UserRole? _parseUserRole(String? roleStr) {
    if (roleStr == null) return null;
    try {
      return UserRole.values.firstWhere((r) => r.name == roleStr);
    } on Exception catch (_) {
      return null;
    }
  }

  String _roleToString(UserRole role) => role.name;

  @override
  void dispose() {
    _authSub.cancel();
    _sessionManager.dispose();
    super.dispose();
  }
}

// AuthException is defined in package:climate_app/core/utils/error_handler.dart
// and re-exported above. No local definition needed.
