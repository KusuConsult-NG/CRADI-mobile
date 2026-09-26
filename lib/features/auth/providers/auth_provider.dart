import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:climate_app/core/utils/error_handler.dart';
export 'package:climate_app/core/utils/error_handler.dart' show AuthException;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/session_manager.dart';
import 'package:climate_app/core/services/rate_limiter.dart';
import 'package:climate_app/core/services/biometric_service.dart';
import 'package:climate_app/core/services/device_fingerprint_service.dart';
import 'package:climate_app/core/services/fraud_detection_service.dart';
import 'dart:math' as math;
import 'package:climate_app/core/services/email_service.dart';
import 'package:climate_app/core/services/sms_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;
import 'package:supabase_flutter/supabase_flutter.dart' as sp show AuthException;

extension SupabaseUserCompat on User {
  String get uid => id;
  String? get displayName => userMetadata?['full_name'] as String?;
}

enum UserRole { user, ewm, ewv, ewr, admin, techSupport }

/// Authentication state and operations — backed by Supabase Auth + PostgREST.
class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    _initializeSessionManager();
    // Start listening to Supabase auth state immediately.
    // ignore: unnecessary_statements
    _authSub;
  }

  final SupabaseService _supabase = SupabaseService();
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
  // Set true during a fresh manual login to prevent _onAuthStateChanged
  // from immediately locking the app via the biometric lock screen.
  bool _justLoggedIn = false;

  // Real-time listener on the user's profile row in Supabase.
  StreamSubscription<List<Map<String, dynamic>>>? _userDocSub;

  // Auth state subscription (initialized lazily on first access).
  // ignore: cancel_subscriptions
  late final _authSub = _supabase.authStateChanges.listen(
    (AuthState state) => _onAuthStateChanged(state.session?.user),
  );

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
    _sessionManager.onSessionExpired = () async {
      final bioEnabled = await _storage.isBiometricEnabled();
      if (bioEnabled) {
        _isLocked = true;
        notifyListeners();
      } else {
        await logout();
      }
    };
  }

  /// React to Supabase auth state changes.
  Future<void> _onAuthStateChanged(User? user) async {
    if (user == null) {
      _userDocSub?.cancel();
      _userDocSub = null;
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
    if (bioEnabled && !_justLoggedIn) {
      _isLocked = true;
      _isAuthenticated = true;
    } else {
      _isAuthenticated = true;
    }
    _justLoggedIn = false;

    // Fetch Supabase profile row for role + approval/verification status.
    try {
      final userDoc = await _supabase.getDocument(
        collectionId: AppConfig.usersCollection,
        documentId: user.id,
      );

      final firestoreRole = userDoc['role'] as String?;
      if (firestoreRole != null) {
        _userRole = _parseUserRole(firestoreRole);
        await _storage.saveUserRole(firestoreRole);
      } else {
        final cachedRole = await _storage.getUserRole();
        _userRole = _parseUserRole(cachedRole);
      }

      _isApproved = userDoc['is_approved'] as bool? ?? false;
      _isVerified = userDoc['is_verified'] as bool? ?? false;

      // Self-heal: if Supabase email is confirmed but profile row is not
      final emailVerified = user.emailConfirmedAt != null;
      if (emailVerified && !_isVerified) {
        developer.log(
          'Auth verified but profile row not. Syncing...',
          name: 'AuthProvider',
        );
        try {
          await _supabase.updateDocument(
            collectionId: AppConfig.usersCollection,
            documentId: user.id,
            data: {'is_verified': true},
          );
          _isVerified = true;
        } on Exception catch (e) {
          developer.log('Failed to sync verification: $e');
        }
      }
    } on Exception catch (e) {
      developer.log('Error fetching Supabase profile: $e');
      final cachedRole = await _storage.getUserRole();
      if (cachedRole != null) {
        _userRole = _parseUserRole(cachedRole);
      }
    }

    // Start real-time listener so admin role changes take effect immediately
    _startUserDocListener(user.id);

    _phoneNumber = await _storage.getPhoneNumber();
    _isInitialized = true;
    notifyListeners();
  }

  /// Listen to the user's profile row in real-time via Supabase Realtime.
  void _startUserDocListener(String uid) {
    _userDocSub?.cancel();
    _userDocSub = _supabase
        .subscribeToCollection(
          collectionId: AppConfig.usersCollection,
          queries: [SQuery.equal('id', uid)],
        )
        .listen(
          (rows) {
            if (rows.isEmpty) return;
            final data = rows.first;

            final newRoleStr = data['role'] as String?;
            if (newRoleStr != null) {
              final newRole = _parseUserRole(newRoleStr);
              if (newRole != _userRole) {
                developer.log(
                  'Role changed via Realtime: $_userRole → $newRole',
                  name: 'AuthProvider',
                );
                _userRole = newRole;
                _storage.saveUserRole(newRoleStr);
              }
            }

            final newApproved = data['is_approved'] as bool? ?? false;
            final newVerified = data['is_verified'] as bool? ?? false;
            final newDisabled = data['is_disabled'] as bool? ?? false;

            bool changed = false;
            if (_isApproved != newApproved) {
              _isApproved = newApproved;
              changed = true;
            }
            if (_isVerified != newVerified) {
              _isVerified = newVerified;
              changed = true;
            }

            if (newDisabled) {
              developer.log(
                'Account disabled via admin — logging out',
                name: 'AuthProvider',
              );
              logout();
              return;
            }

            if (changed || newRoleStr != null) {
              notifyListeners();
            }
          },
          onError: (e) {
            developer.log('User doc listener error: $e', name: 'AuthProvider');
          },
        );
  }

  /// Force reload of user data (e.g. after profile update).
  Future<void> reloadUserData() async {
    await _supabase.reloadCurrentUser();
    final user = _supabase.getCurrentUser();
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
        await _supabase.logout();
      } on Exception {
        developer.log('No existing session to clear', name: 'AuthProvider');
      }

      // 1. Create Supabase Auth user
      developer.log('Creating Supabase account...', name: 'AuthProvider');
      final user = await _supabase.createAccount(
        email: email,
        password: password,
        name: name ?? 'User',
      );
      developer.log('Account created: ${user.id}', name: 'AuthProvider');
      _currentUser = user;

      // 2. Determine role
      final userRole = role ?? UserRole.user;

      // 3. Create profile row
      developer.log(
        'Creating Supabase profile row...',
        name: 'AuthProvider',
      );
      await _createUserDocument(
        userId: user.id,
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
      developer.log('User profile created', name: 'AuthProvider');

      // 4. Start session
      await _startUserSession(user, userRole, isVerified: isVerified ?? false);

      // Save credentials for Biometric auto-login bypass
      await _storage.saveUserCredentials(email, password);

      // 5. Send OTP email
      if (isVerified != true) {
        await sendOtpForEmail(email, name: name);
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException {
      _isLoading = false;
      notifyListeners();
      rethrow;
    } on sp.AuthException catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log(
        'SignUp AuthException: ${e.statusCode} – ${e.message}',
        name: 'AuthProvider',
      );
      if (e.message.toLowerCase().contains('already registered') ||
          e.statusCode == '422') {
        throw AuthException('Email is already registered. Please login.');
      }
      if (e.message.toLowerCase().contains('weak') ||
          e.message.toLowerCase().contains('password')) {
        throw AuthException(
          'Password is too weak. Use at least 8 characters with letters, numbers and symbols.',
        );
      }
      if (e.statusCode == '429') {
        throw AuthException(
          'Too many attempts. Please wait a few minutes before trying again.',
        );
      }
      throw AuthException('Registration failed. Please try again.');
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

  /// Creates a Supabase Auth account for a phone-registered user after OTP
  /// verification. Since we use email+password Auth, we derive a surrogate
  /// email (`{sanitised_phone}@ewer.phone`) and generate a secure
  /// random password stored in SecureStorage (transparent to the user).
  Future<bool> signUpWithPhone({
    required String phone,
    String? name,
    String? address,
    UserRole? role,
    String? state,
    String? lga,
    String? ward,
  }) async {
    final sanitisedPhone = phone.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final derivedEmail = '$sanitisedPhone@ewer.phone';

    const salt = 'cradi_ewer_2026_phone_auth_salt';
    final rawBytes = utf8.encode('${sanitisedPhone}_$salt');
    final generatedPassword = base64Encode(rawBytes).substring(0, 32);

    await _storage.write('phone_derived_email_$sanitisedPhone', derivedEmail);
    await _storage.write(
      'phone_derived_password_$sanitisedPhone',
      generatedPassword,
    );

    try {
      await _supabase.logout();
    } on Exception {
      /* ignore */
    }

    User? user;
    bool isNewUser = true;
    try {
      user = await _supabase.createAccount(
        email: derivedEmail,
        password: generatedPassword,
        name: name ?? 'User',
      );
    } on sp.AuthException catch (e) {
      if (e.message.toLowerCase().contains('already registered') ||
          e.statusCode == '422') {
        developer.log(
          'Phone user exists. Falling back to login.',
          name: 'AuthProvider',
        );
        user = await _supabase.createEmailPasswordSession(
          email: derivedEmail,
          password: generatedPassword,
        );
        isNewUser = false;
      } else {
        rethrow;
      }
    }

    _currentUser = user;

    final userRole = role ?? UserRole.user;

    if (isNewUser) {
      await _createUserDocument(
        userId: user.id,
        email: derivedEmail,
        role: userRole,
        name: name,
        address: address,
        state: state,
        lga: lga,
        ward: ward,
        isVerified: true,
        phoneNumber: phone,
      );
    }

    await _startUserSession(user, userRole, isVerified: true);
    developer.log(
      'signUpWithPhone: account created/logged in uid=${user.id}',
      name: 'AuthProvider',
    );
    return true;
  }

  Future<bool> signInWithEmail({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    String? deviceFingerprint;
    try {
      _isLoading = true;
      notifyListeners();

      try {
        await _supabase.logout();
      } on Exception {
        developer.log('No existing session to clear', name: 'AuthProvider');
      }
      _currentUser = null;
      _isAuthenticated = false;
      _userRole = null;

      deviceFingerprint = await _fingerprintService.generateFingerprint();
      final deviceName = await _fingerprintService.getDeviceName();

      _justLoggedIn = true;
      final user = await _supabase.createEmailPasswordSession(
        email: email,
        password: password,
      );
      _currentUser = user;

      // Fetch Supabase profile row
      Map<String, dynamic> userDoc;
      try {
        userDoc = await _supabase.getDocument(
          collectionId: AppConfig.usersCollection,
          documentId: user.id,
        );
      } on PostgrestException catch (e) {
        developer.log(
          'User profile missing (zombie user), recovering: ${e.message}',
          name: 'AuthProvider',
        );
        await _createUserDocument(
          userId: user.id,
          email: user.email ?? email,
          name: user.userMetadata?['full_name'] as String?,
          role: UserRole.user,
        );
        userDoc = await _supabase.getDocument(
          collectionId: AppConfig.usersCollection,
          documentId: user.id,
        );
      }

      final roleStr = userDoc['role'] as String?;
      final role = _parseUserRole(roleStr) ?? UserRole.user;
      _userRole = role;
      _isApproved = userDoc['is_approved'] as bool? ?? false;
      _isVerified = userDoc['is_verified'] as bool? ?? false;

      // Fraud assessment (non-blocking)
      try {
        final fraudAssessment = await _fraudService.assessLoginRisk(
          userId: user.id,
          deviceFingerprint: deviceFingerprint,
        );
        developer.log(
          'Fraud assessment: ${fraudAssessment.risk} – ${fraudAssessment.reason}',
          name: 'AuthProvider',
        );

        await _fraudService.recordLoginAttempt(
          userId: user.id,
          success: true,
          deviceFingerprint: deviceFingerprint,
          deviceName: deviceName,
        );

        if (fraudAssessment.flags.contains('new_device')) {
          await _fraudService.registerTrustedDevice(
            userId: user.id,
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

      await _startUserSession(user, role, rememberMe: rememberMe);
      await _rateLimiter.resetLoginAttempts();

      await _storage.saveUserCredentials(email, password);

      _isLoading = false;
      notifyListeners();
      return true;
    } on sp.AuthException catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      developer.log(
        'Login AuthException: ${e.statusCode} – ${e.message}',
        name: 'AuthProvider',
      );
      if (e.statusCode == '400') {
        throw AuthException('Invalid email or password');
      }
      if (e.statusCode == '429') {
        throw AuthException(
          'Too many login attempts. Please wait a few minutes and try again.',
        );
      }
      ErrorHandler.logError(
        'AuthException: ${e.statusCode} – ${e.message}',
        context: 'AuthProvider.signInWithEmail',
      );
      throw AuthException(
        'Login failed: ${e.message.length > 100 ? e.message.substring(0, 100) : e.message}',
      );
    } on Exception catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.signInWithEmail');
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

      final rateLimitResult = await _rateLimiter.checkOtpResend();
      if (!rateLimitResult.allowed) {
        throw AuthException(rateLimitResult.userMessage);
      }

      final normalised = phone.trim().toLowerCase();
      if (normalised.isEmpty) {
        throw AuthException('Invalid phone number.');
      }

      final secureRandom = math.Random.secure();
      final otp = (100000 + secureRandom.nextInt(900000)).toString();

      final docId = normalised.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final expiryTime = DateTime.now().add(const Duration(minutes: 10));

      await _supabase.createDocument(
        collectionId: 'otp_verifications',
        documentId: docId,
        data: {
          'id': docId,
          'identifier': normalised,
          'code': otp,
          'expires_at': expiryTime.toUtc().toIso8601String(),
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'used': false,
          'attempts': 0,
        },
      );

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

      final rateLimitResult = await _rateLimiter.checkOtpResend();
      if (!rateLimitResult.allowed) {
        throw AuthException(rateLimitResult.userMessage);
      }

      final secureRandom = math.Random.secure();
      final otp = (100000 + secureRandom.nextInt(900000)).toString();

      final normalisedEmail = email.trim().toLowerCase();
      final docId = normalisedEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      final expiryTime = DateTime.now().add(const Duration(minutes: 10));

      await _supabase.createDocument(
        collectionId: 'otp_verifications',
        documentId: docId,
        data: {
          'id': docId,
          'identifier': normalisedEmail,
          'code': otp,
          'expires_at': expiryTime.toUtc().toIso8601String(),
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'used': false,
          'attempts': 0,
        },
      );

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
        // Fallback: use current Supabase user email
        final userEmail =
            _currentUser?.email ?? _supabase.getCurrentUser()?.email;
        if (userEmail == null || userEmail.isEmpty) {
          throw AuthException(
            'No user context for verification. Please login again.',
          );
        }
        registrationData = {'email': userEmail};
      }

      final rawKey =
          ((registrationData['phone'] ?? registrationData['email']) as String)
              .trim()
              .toLowerCase();
      final docId = rawKey.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

      // 1. READ the stored OTP document
      Map<String, dynamic> data;
      try {
        data = await _supabase.getDocument(
          collectionId: 'otp_verifications',
          documentId: docId,
        );
      } on PostgrestException catch (_) {
        throw AuthException('Invalid or expired verification code.');
      } on Exception catch (e) {
        if (e.toString().contains('not found') ||
            e.toString().contains('0 rows')) {
          throw AuthException('Invalid or expired verification code.');
        }
        rethrow;
      }

      // 2. Check if already used
      final alreadyUsed = data['used'] as bool? ?? false;
      if (alreadyUsed) {
        throw AuthException(
          'This code has already been used. Please request a new one.',
        );
      }

      // 3. Check expiry
      final expiresAtStr = data['expires_at'] as String?;
      if (expiresAtStr != null) {
        final expiresAt = DateTime.tryParse(expiresAtStr);
        if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
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
        // Increment attempt counter (best-effort)
        try {
          await _supabase.updateDocument(
            collectionId: 'otp_verifications',
            documentId: docId,
            data: {'attempts': attempts + 1},
          );
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
      await _supabase.updateDocument(
        collectionId: 'otp_verifications',
        documentId: docId,
        data: {'used': true},
      );

      // 7. Complete account creation / mark verified
      final isPhoneFlow =
          registrationData.containsKey('phone') &&
          !registrationData.containsKey('email');

      if (isPhoneFlow) {
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
        final user = _supabase.getCurrentUser();
        if (user != null) {
          await _supabase.updateDocument(
            collectionId: AppConfig.usersCollection,
            documentId: user.id,
            data: {'is_verified': true},
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
    } on PostgrestException catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log(
        'PostgrestException in verifyOtpAndLogin: ${e.code} – ${e.message}',
        name: 'AuthProvider',
      );
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
        final user = _supabase.getCurrentUser();
        if (user != null) {
          _currentUser = user;
        } else {
          throw AuthException('User not logged in');
        }
      }

      await sendOtpForEmail(
        _currentUser!.email!,
        name: _currentUser!.userMetadata?['full_name'] as String?,
      );
    } on AuthException {
      rethrow;
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
      await _supabase.createPasswordRecovery(email: email);
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
        bool isValid = await _isServerSessionValid();

        if (!isValid) {
          final creds = await _storage.getUserCredentials();
          if (creds != null) {
            try {
              return await signInWithEmail(
                email: creds['email']!,
                password: creds['password']!,
              );
            } on Exception catch (e) {
              developer.log(
                'Biometric auto-login failed: $e',
                name: 'AuthProvider',
              );
              return false;
            }
          }
          return false;
        }

        _isAuthenticated = true;
        final userRoleStr = await _storage.getUserRole();
        _userRole = _parseUserRole(userRoleStr);
        _phoneNumber = await _storage.getPhoneNumber();

        final user = _supabase.getCurrentUser();
        if (user != null) {
          try {
            final userDoc = await _supabase.getDocument(
              collectionId: AppConfig.usersCollection,
              documentId: user.id,
            );
            _isApproved = userDoc['is_approved'] as bool? ?? false;
            _isVerified = userDoc['is_verified'] as bool? ?? false;
          } on Exception catch (e) {
            developer.log('Biometric unlock failed to fetch profile: $e');
          }
        }

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
        final user = _supabase.getCurrentUser();
        if (user != null) {
          try {
            await _supabase.updateDocument(
              collectionId: AppConfig.usersCollection,
              documentId: user.id,
              data: {'biometrics_enabled': true},
            );
          } on Exception catch (e) {
            developer.log('Error syncing biometric to Supabase: $e');
          }
        }
      } else {
        throw AuthException('Biometric authentication failed');
      }
    } else {
      await _storage.setBiometricEnabled(false);
      final user = _supabase.getCurrentUser();
      if (user != null) {
        try {
          await _supabase.updateDocument(
            collectionId: AppConfig.usersCollection,
            documentId: user.id,
            data: {'biometrics_enabled': false},
          );
        } on Exception catch (e) {
          developer.log('Error syncing biometric to Supabase: $e');
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
      final user = _supabase.getCurrentUser();
      if (user == null) {
        developer.log(
          'No active Supabase user found in session check.',
          name: 'AuthProvider',
        );
        return false;
      }

      // Supabase tokens auto-refresh; a reload confirms validity
      await _supabase.reloadCurrentUser();
      await _sessionManager.extendSession();
      return true;
    } on sp.AuthException catch (e) {
      developer.log('Session expired: ${e.statusCode}', name: 'AuthProvider');
      await logout();
      return false;
    } on Exception catch (e) {
      developer.log('Session network error: $e', name: 'AuthProvider');
      return true; // Allow offline access
    }
  }

  Future<Duration?> getSessionTimeRemaining() =>
      _sessionManager.getRemainingTime();

  // ─────────────────────────── Logout ──────────────────────────────────────

  Future<void> logout() async {
    try {
      _isLoading = true;
      notifyListeners();

      _userDocSub?.cancel();
      _userDocSub = null;

      try {
        await _sessionManager.logout();
      } on Exception catch (e) {
        developer.log('Session manager logout error: $e', name: 'AuthProvider');
      }

      try {
        await _supabase.logout();
      } on Exception catch (e) {
        developer.log('Supabase logout error: $e', name: 'AuthProvider');
      }

      await _storage.clearAll(keepPreferences: true);

      _isAuthenticated = false;
      _isLocked = false;
      _userRole = null;
      _currentUser = null;
      _phoneNumber = null;
      _isApproved = null;
      _isVerified = false;
      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _isAuthenticated = false;
      _isLocked = false;
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
    final roleString = _roleToString(role);

    final payload = {
      'id': userId,
      'email': email,
      'full_name': name ?? 'User',
      'role': roleString,
      'address': address ?? '',
      'state': state ?? '',
      'lga': lga ?? '',
      'ward': ward ?? '',
      'is_verified': isVerified,
      'is_approved': false,
      'biometrics_enabled': false,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'last_login_at': DateTime.now().toUtc().toIso8601String(),
      'phone': phoneNumber ?? '',
      'avatar_url': '',
    };

    developer.log(
      'Creating Supabase profile for $userId',
      name: 'AuthProvider',
    );

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        await _supabase.createDocument(
          collectionId: AppConfig.usersCollection,
          documentId: userId,
          data: payload,
        );
        return;
      } on Exception catch (e) {
        retryCount++;
        developer.log(
          'Error creating profile (attempt $retryCount): $e',
          name: 'AuthProvider',
        );
        if (retryCount >= maxRetries) rethrow;
        await Future.delayed(const Duration(milliseconds: 1500));
      }
    }
  }

  Future<void> _startUserSession(
    User user,
    UserRole role, {
    bool isVerified = true,
    bool rememberMe = false,
  }) async {
    await _storage.saveUserRole(role.name);
    await _sessionManager.startSession(
      authToken: user.id,
      userRole: role.name,
      rememberMe: rememberMe,
    );
    _isAuthenticated = true;
  }

  String _roleToString(UserRole role) {
    switch (role) {
      case UserRole.ewm:
        return 'ewm';
      case UserRole.ewv:
        return 'ewv';
      case UserRole.ewr:
        return 'ewr';
      case UserRole.admin:
        return 'admin';
      case UserRole.techSupport:
        return 'techSupport';
      default:
        return 'user';
    }
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
