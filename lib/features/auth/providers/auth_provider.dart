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
import 'package:climate_app/core/services/sms_service.dart';
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
  // Set to true during a fresh manual login to prevent _onAuthStateChanged
  // from immediately re-locking the app via the biometric lock screen.
  bool _justLoggedIn = false;

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

    // Force-refresh the token so any custom claims (role, admin) set via
    // Firebase Admin SDK are immediately included. Without this, Firestore
    // security rules see stale claims and deny reads for newly-promoted users.
    try {
      await user.getIdToken(true);
      developer.log(
        'Token refreshed — custom claims loaded',
        name: 'AuthProvider',
      );
    } on Exception catch (e) {
      developer.log(
        'Token refresh failed (non-fatal): $e',
        name: 'AuthProvider',
      );
    }

    // Load onboarding status
    final prefs = await SharedPreferences.getInstance();
    _hasCompletedOnboarding =
        prefs.getBool('has_completed_onboarding') ?? false;

    // Check biometric lock — but only on cold-start/app-resume.
    // If the user JUST logged in manually (_justLoggedIn == true), skip locking
    // so they are taken directly to the dashboard.
    final bioEnabled = await _storage.isBiometricEnabled();
    if (bioEnabled && !_justLoggedIn) {
      _isLocked = true;
      _isAuthenticated = false;
    } else {
      _isAuthenticated = true;
    }
    _justLoggedIn = false; // Reset flag regardless

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

      // 6. Send OTP email
      if (isVerified != true) {
        await sendOtpForEmail(email, name: name);
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
      // Map known codes to user-friendly messages.
      // IMPORTANT: never pass e.message raw — Firebase SDK internal strings
      // like 'An internal error has occurred. [ Pin verification failed' must
      // never reach the UI.
      switch (e.code) {
        case 'email-already-in-use':
          throw AuthException('Email is already registered. Please login.');
        case 'invalid-email':
          throw AuthException('Please enter a valid email address.');
        case 'weak-password':
          throw AuthException(
            'Password is too weak. Use at least 8 characters with letters, numbers and symbols.',
          );
        case 'operation-not-allowed':
          throw AuthException(
            'Email registration is currently disabled. Please contact support.',
          );
        case 'network-request-failed':
          throw AuthException(
            'Network error. Please check your connection and try again.',
          );
        case 'too-many-requests':
          throw AuthException(
            'Too many attempts. Please wait a few minutes before trying again.',
          );
        default:
          throw AuthException('Registration failed. Please try again.');
      }
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

  // ─────────────────────────── Phone Sign-Up ───────────────────────────────

  /// Creates a Firebase Auth account for a phone-registered user after OTP
  /// verification. Since Firebase Auth requires email+password, we derive a
  /// surrogate email (`{sanitised_phone}@ewer.phone`) and generate a secure
  /// random password that is stored in SecureStorage so the user can log in
  /// again without knowing it (transparent to them).
  Future<bool> signUpWithPhone({
    required String phone,
    String? name,
    String? address,
    UserRole? role,
    String? state,
    String? lga,
    String? ward,
  }) async {
    // Derive a stable Firebase-safe email for the phone user
    final sanitisedPhone = phone.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final derivedEmail = '$sanitisedPhone@ewer.phone';

    // Generate a 32-char URL-safe secure password
    final rand = math.Random.secure();
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_';
    final generatedPassword = List.generate(
      32,
      (_) => chars[rand.nextInt(chars.length)],
    ).join();

    // Store derived credentials so the user can re-authenticate later
    await _storage.write('phone_derived_email_$sanitisedPhone', derivedEmail);
    await _storage.write(
      'phone_derived_password_$sanitisedPhone',
      generatedPassword,
    );

    // Clear any stale Firebase session
    try {
      await _firebase.logout();
    } on Exception {
      /* ignore */
    }

    // Create Firebase Auth account or fall back if exists
    User? user;
    try {
      user = await _firebase.createAccount(
        email: derivedEmail,
        password: generatedPassword,
        name: name ?? 'User',
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        developer.log(
          'Phone user exists. Falling back to login.',
          name: 'AuthProvider',
        );
        user = await _firebase.createEmailPasswordSession(
          email: derivedEmail,
          password: generatedPassword,
        );
      } else {
        rethrow;
      }
    }

    _currentUser = user;

    final userRole = role ?? UserRole.user;

    // Create Firestore user document (phone stored as primary identifier)
    await _createUserDocument(
      userId: user.uid,
      email: derivedEmail,
      role: userRole,
      name: name,
      address: address,
      state: state,
      lga: lga,
      ward: ward,
      isVerified: true, // OTP already verified before this call
      phoneNumber: phone,
    );

    await _startUserSession(user, userRole, isVerified: true);
    developer.log(
      'signUpWithPhone: account created/logged in uid=${user.uid}',
      name: 'AuthProvider',
    );
    return true;
  }

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

      // Note: rate-limit check is enforced inside firebase_service.createEmailPasswordSession
      // to keep the logic co-located with the actual auth call. No need to duplicate here.

      // Device fingerprint for fraud tracking
      deviceFingerprint = await _fingerprintService.generateFingerprint();
      final deviceName = await _fingerprintService.getDeviceName();

      // Sign in with Firebase — flag prevents biometric lock from triggering
      // in the _onAuthStateChanged callback for this fresh login.
      _justLoggedIn = true;
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
      _justLoggedIn = false;
      notifyListeners();
      developer.log(
        'Login FirebaseAuthException: ${e.code} – ${e.message}',
        name: 'AuthProvider',
      );
      // Credential errors
      if (e.code == 'invalid-credential' ||
          e.code == 'wrong-password' ||
          e.code == 'user-not-found') {
        throw AuthException('Invalid email or password');
      }
      // Rate / brute-force
      if (e.code == 'too-many-requests' || e.code == 'rate-limited') {
        throw AuthException(
          'Too many login attempts. Please wait a few minutes and try again.',
        );
      }
      // Account disabled
      if (e.code == 'user-disabled') {
        throw AuthException(
          'This account has been disabled. Please contact support.',
        );
      }
      // Network / connectivity
      if (e.code == 'network-request-failed') {
        throw AuthException('Login failed. Please check your connection.');
      }
      // Default: log the raw code to Crashlytics, show generic message
      ErrorHandler.logError(
        'Unhandled FirebaseAuthException: ${e.code} – ${e.message}',
        context: 'AuthProvider.signInWithEmail',
      );
      throw AuthException(
        'Login failed (${e.code}): ${e.message ?? "No additional details"}',
      );
    } on Exception catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.signInWithEmail');
      // Surface the actual exception type+message in debug for field diagnosis.
      // In release this is scrubbed by ErrorHandler and never shown raw.
      if (kDebugMode) {
        throw AuthException(
          'Login error: ${e.runtimeType} – ${e.toString().substring(0, e.toString().length.clamp(0, 200))}',
        );
      }
      throw AuthException(
        'An unexpected error occurred during login. Please try again.',
      );
    }
  }

  // ─────────────────────────── OTP ─────────────────────────────────────────

  Future<bool> sendOtpForPhone(String phone) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Rate limiting
      final rateLimitResult = await _rateLimiter.checkOtpResend();
      if (!rateLimitResult.allowed) {
        throw AuthException(rateLimitResult.userMessage);
      }

      // Normalise and validate
      final normalised = phone.trim().toLowerCase();
      if (normalised.isEmpty) {
        throw AuthException('Invalid phone number.');
      }

      // Generate a cryptographically secure 6-digit OTP
      final secureRandom = math.Random.secure();
      final otp = (100000 + secureRandom.nextInt(900000)).toString();

      // Doc ID = sanitised phone (e.g. +2348012345678 → _2348012345678)
      final docId = normalised.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final expiryTime = DateTime.now().add(const Duration(minutes: 10));

      await FirebaseFirestore.instance
          .collection('otp_verifications')
          .doc(docId)
          .set({
            'phone': normalised,
            'code': otp,
            'expiresAt': Timestamp.fromDate(expiryTime),
            'createdAt': FieldValue.serverTimestamp(),
            'used': false,
            'attempts': 0,
          });

      // Send OTP via Termii SMS
      final smsService = SmsService();
      if (!smsService.isReady) {
        throw AuthException(
          'SMS service is not configured. Please contact support.',
        );
      }

      final messageId = await smsService.sendOtp(to: phone, otp: otp);
      if (messageId == null) {
        throw AuthException('Failed to send SMS. Please try again.');
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
      ErrorHandler.logError(e, context: 'AuthProvider.sendOtpForPhone');
      throw AuthException('Failed to send verification SMS.');
    }
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

      // Normalise email to lowercase to prevent case-mismatch on doc ID
      final normalisedEmail = email.trim().toLowerCase();
      final docId = normalisedEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final expiryTime = DateTime.now().add(const Duration(minutes: 10));
      await FirebaseFirestore.instance
          .collection('otp_verifications')
          .doc(docId)
          .set({
            'email': normalisedEmail,
            'code': otp,
            'expiresAt': Timestamp.fromDate(expiryTime),
            'createdAt': FieldValue.serverTimestamp(),
            'used': false,
            'attempts': 0,
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

      if (registrationData == null ||
          (!registrationData.containsKey('email') &&
              !registrationData.containsKey('phone'))) {
        // Fallback: use current Firebase user email
        final userEmail =
            _currentUser?.email ?? _firebase.getCurrentUser()?.email;
        if (userEmail == null || userEmail.isEmpty) {
          throw AuthException(
            'No user context for verification. Please login again.',
          );
        }
        registrationData = {'email': userEmail};
      }

      // Resolve doc ID — prefer phone key (phone flow) over email key
      final rawKey =
          ((registrationData['phone'] ?? registrationData['email']) as String)
              .trim()
              .toLowerCase();
      final docId = rawKey.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      // 1. READ the stored OTP document (no write required — avoids permission-denied)
      final docRef = FirebaseFirestore.instance
          .collection('otp_verifications')
          .doc(docId);

      final docSnap = await docRef.get();
      if (!docSnap.exists) {
        throw AuthException('Invalid or expired verification code.');
      }

      final data = docSnap.data()!;

      // 2. Check if already used
      final alreadyUsed = data['used'] as bool? ?? false;
      if (alreadyUsed) {
        throw AuthException(
          'This code has already been used. Please request a new one.',
        );
      }

      // 3. Check expiry
      final expiresAt = data['expiresAt'];
      if (expiresAt != null && expiresAt is Timestamp) {
        if (expiresAt.toDate().isBefore(DateTime.now())) {
          throw AuthException(
            'Verification code has expired. Please request a new one.',
          );
        }
      }

      // 4. Check attempt counter — lock after 5 failed tries
      final attempts = (data['attempts'] as int?) ?? 0;
      if (attempts >= 5) {
        throw AuthException(
          'Too many incorrect attempts. Please request a new code.',
        );
      }

      // 5. Compare submitted OTP against stored code
      final storedCode = (data['code'] as String? ?? '').trim();
      final submittedCode = otp.trim();
      if (storedCode.isEmpty || storedCode != submittedCode) {
        // Increment attempt counter (best-effort, non-blocking)
        try {
          await docRef.update({'attempts': FieldValue.increment(1)});
        } on Exception catch (_) {}
        final remaining = 4 - attempts;
        if (remaining <= 0) {
          throw AuthException(
            'Too many incorrect attempts. Please request a new code.',
          );
        }
        throw AuthException(
          'Incorrect code. $remaining attempt${remaining == 1 ? '' : 's'} remaining.',
        );
      }

      // 6. Mark the OTP as used
      await docRef.update({'used': true});

      // 7. Complete account creation / mark verified
      final isPhoneFlow =
          registrationData.containsKey('phone') &&
          !registrationData.containsKey('email');

      if (isPhoneFlow) {
        // Phone registration: Firebase account doesn't exist yet — create it now.
        await signUpWithPhone(
          phone: registrationData['phone'] as String,
          name: registrationData['name'] as String?,
          address: registrationData['address'] as String?,
          role: registrationData['role'] as UserRole?,
          state: registrationData['state'] as String?,
          lga: registrationData['lga'] as String?,
          ward: registrationData['ward'] as String?,
        );
      } else {
        // Email registration: account already exists — just mark as verified.
        final user = _firebase.getCurrentUser();
        if (user != null) {
          await _firebase.updateDocument(
            collectionId: AppConfig.usersCollection,
            documentId: user.uid,
            data: {'isVerified': true},
          );
          _isVerified = true;
        }
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException {
      _isLoading = false;
      notifyListeners();
      rethrow;
    } on FirebaseException catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log(
        'FirebaseException in verifyOtpAndLogin: ${e.code} – ${e.message}',
        name: 'AuthProvider',
      );
      if (e.code == 'not-found') {
        throw AuthException('Invalid or expired verification code.');
      }
      throw AuthException('Verification failed. Please try again.');
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
    } on Exception catch (_) {
      throw AuthException(
        'Failed to resend verification code. Please try again.',
      );
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
    // Map the enum explicitly to strings that Firestore rules expect
    final roleString = role == UserRole.user
        ? 'user'
        : role == UserRole.ewm
        ? 'ewm'
        : role == UserRole.ewv
        ? 'ewv'
        : role == UserRole.ewr
        ? 'ewr'
        : role == UserRole.admin
        ? 'admin'
        : role == UserRole.techSupport
        ? 'techSupport'
        : 'user';

    final payload = {
      'email': email,
      'name': name ?? 'User',
      'role': roleString,
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
    };

    developer.log(
      'Creating Firestore document for $userId with payload: $payload',
      name: 'AuthProvider',
    );

    // Structural retry loop to handle Firebase Auth token propagation delays
    // causing immediate PERMISSION_DENIED errors on initial account creation
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        await _firebase.createDocument(
          collectionId: AppConfig.usersCollection,
          documentId: userId,
          data: payload,
        );
        return; // Success
      } on Exception catch (e) {
        retryCount++;
        developer.log(
          'Error creating user document (attempt $retryCount): $e',
          name: 'AuthProvider',
        );
        if (retryCount >= maxRetries) rethrow;
        // Wait 1.5s for the Auth JWT to fully propagate to the Firestore client SDK
        await Future.delayed(const Duration(milliseconds: 1500));
      }
    }
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
    switch (roleStr) {
      case 'user':
        return UserRole.user;
      case 'ewm':
        return UserRole.ewm;
      case 'ewv':
        return UserRole.ewv;
      case 'ewr':
        return UserRole.ewr;
      case 'admin':
        return UserRole.admin;
      case 'techSupport':
        return UserRole.techSupport;
      default:
        return null;
    }
  }

  @override
  void dispose() {
    _authSub.cancel();
    _sessionManager.dispose();
    super.dispose();
  }
}

// AuthException is defined in package:climate_app/core/utils/error_handler.dart
// and re-exported above. No local definition needed.
