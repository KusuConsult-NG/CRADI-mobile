import 'dart:async';
import 'dart:developer' as developer;
import 'package:climate_app/core/utils/error_handler.dart';
export 'package:climate_app/core/utils/error_handler.dart'
    show AuthException, EmailNotConfirmedException;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/notification_service.dart';
import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/session_manager.dart';
import 'package:climate_app/core/services/rate_limiter.dart';
import 'package:climate_app/core/services/biometric_service.dart';
import 'package:climate_app/core/services/device_fingerprint_service.dart';
import 'package:climate_app/core/services/fraud_detection_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/utils/validators.dart';

enum UserRole {
  user,
  ewm,
  ewv,
  ewr,
  ldpCoordinator,
  projectStaff,
  admin,
  techSupport,
}

extension UserRoleValue on UserRole {
  /// The value stored in `profiles.role`.
  String get dbValue => switch (this) {
    UserRole.ldpCoordinator => 'ldp_coordinator',
    UserRole.projectStaff => 'project_staff',
    _ => name,
  };

  /// Parses a `profiles.role` value (null when unknown).
  static UserRole? fromDb(String? value) {
    if (value == null) return null;
    for (final role in UserRole.values) {
      if (role.dbValue == value) return role;
    }
    return null;
  }
}

/// Authentication state and operations — backed by Supabase Auth and the
/// `profiles` table.
///
/// * Sign-up passes the profile fields as user metadata; a database trigger
///   creates the `profiles` row. The client never inserts it.
/// * Email verification and password recovery use Supabase's 6-digit OTPs.
/// * Phone accounts use Supabase phone OTP (SMS provider configured in the
///   Supabase dashboard).
/// * The session (incl. refresh token) is persisted by supabase_flutter in
///   secure storage; the biometric lock re-uses it — no password is stored.
/// * Role / approval / disabled changes arrive through a realtime
///   subscription on the user's own profile row.
class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    _initializeSessionManager();
    unawaited(_storage.purgeLegacyCredentials());
    _authSub = _db.authStateChanges.listen(
      _onAuthEvent,
      onError: (Object e) =>
          developer.log('Auth stream error: $e', name: 'AuthProvider'),
    );
    if (!SupabaseService.isReady) {
      // No backend configured: behave as signed out.
      unawaited(_handleSignedOut());
    }
  }

  final SupabaseService _db = SupabaseService();
  bool _isAuthenticated = false;
  UserRole? _userRole;
  String? _phoneNumber;
  bool _isLoading = false;
  sb.User? _currentUser;
  bool? _isApproved;
  bool _isVerified = false;
  String? _ward;

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
  // Set during an explicit sign-in / OTP verification so the sign-in handler
  // does not immediately re-lock the app behind the biometric screen.
  bool _justLoggedIn = false;
  // True while a password-recovery session is active (verifyOTP recovery →
  // updateUser → signOut); auth events are ignored meanwhile.
  bool _recovering = false;
  // Set when the profile row says the account is disabled.
  bool _accountDisabled = false;

  // Email awaiting OTP confirmation (sign-up without a session yet).
  String? _pendingEmail;
  // Phone registration metadata, re-sent with an OTP resend.
  Map<String, dynamic>? _pendingPhoneMetadata;
  // NDPA consent to record once a session exists.
  Map<String, String>? _pendingNdpaConsent;

  // Realtime listener on the user's profile row.
  StreamSubscription<Map<String, dynamic>?>? _profileSub;
  late final StreamSubscription<sb.AuthState> _authSub;

  // Single in-flight sign-in handling per user.
  Future<void>? _signInFuture;
  String? _signInUid;

  /// Roles that may cast a peer-verification vote (`is_verifier()`).
  static const Set<UserRole> verifierRoles = {
    UserRole.ewm,
    UserRole.ewv,
    UserRole.ewr,
    UserRole.admin,
  };

  /// Roles that may approve / reject / reopen reports.
  static const Set<UserRole> statusManagerRoles = {
    UserRole.ewv,
    UserRole.ewr,
    UserRole.ldpCoordinator,
    UserRole.projectStaff,
    UserRole.admin,
  };

  bool get isAuthenticated => _isAuthenticated;

  /// The effective role, matching the database's `app_role()`: the stored
  /// role only counts once an admin has approved the account and it is not
  /// disabled; otherwise the user is treated as a plain [UserRole.user].
  /// Use this for all UI gating.
  UserRole? get userRole {
    final raw = _userRole;
    if (raw == null) return null;
    return (_isApproved == true && !_accountDisabled) ? raw : UserRole.user;
  }

  /// The role stored on the profile (requested or assigned), regardless of
  /// approval. For display only.
  UserRole? get rawUserRole => _userRole;

  /// The signed-in user's ward (from the profile row).
  String? get ward => _ward;

  /// Whether the user may cast a peer-verification vote on a report (mirrors
  /// the `verifications_insert` policy).
  bool canVoteOn({String? reporterId, String? reportWard}) {
    final role = userRole;
    if (role == null || !verifierRoles.contains(role)) return false;
    if (reporterId != null && reporterId == _currentUser?.id) return false;
    if (role == UserRole.ewm) {
      final mine = (_ward ?? '').trim().toLowerCase();
      return mine.isNotEmpty && mine == (reportWard ?? '').trim().toLowerCase();
    }
    return true;
  }

  /// Whether the user may approve / reject / reopen a report (mirrors the
  /// `guard_report_update` trigger).
  bool canManageReportStatus({String? reporterId}) {
    final role = userRole;
    if (role == null || !statusManagerRoles.contains(role)) return false;
    if (role != UserRole.admin &&
        reporterId != null &&
        reporterId == _currentUser?.id) {
      return false;
    }
    return true;
  }

  bool get isLoading => _isLoading;
  String? get phoneNumber => _phoneNumber;
  sb.User? get currentUser => _currentUser;
  bool? get isApproved => _isApproved;
  bool get isVerified => _isVerified;
  bool get isInitialized => _isInitialized;
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;
  bool get isLocked => _isLocked;

  /// Email of the account waiting for OTP confirmation, if any.
  String? get pendingEmail => _pendingEmail ?? _currentUser?.email;

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

  Future<void> _onAuthEvent(sb.AuthState state) async {
    final session = state.session;
    switch (state.event) {
      case sb.AuthChangeEvent.passwordRecovery:
        _recovering = true;
        return;
      case sb.AuthChangeEvent.signedOut:
        await _handleSignedOut();
        return;
      case sb.AuthChangeEvent.initialSession:
      case sb.AuthChangeEvent.signedIn:
        if (_recovering) return;
        if (session == null) {
          await _handleSignedOut();
          return;
        }
        await _ensureSignedIn(session.user);
        return;
      default:
        // tokenRefreshed / userUpdated / mfa: keep the user object fresh
        // without re-running the sign-in flow (which would re-lock the app).
        if (session != null && !_recovering) {
          _currentUser = session.user;
          if (state.event == sb.AuthChangeEvent.userUpdated) {
            notifyListeners();
          }
        }
    }
  }

  Future<void> _ensureSignedIn(sb.User user) {
    final inFlight = _signInFuture;
    if (_signInUid == user.id && inFlight != null) return inFlight;
    _signInUid = user.id;
    return _signInFuture = _handleSignedIn(user);
  }

  Future<void> _handleSignedOut() async {
    await _profileSub?.cancel();
    _profileSub = null;
    _signInFuture = null;
    _signInUid = null;
    _currentUser = null;
    _isAuthenticated = false;
    _userRole = null;
    _isApproved = null;
    _ward = null;
    // Load onboarding status here too, otherwise logged-out users are sent
    // back to /onboarding on every cold start.
    await _loadOnboardingStatus();
    unawaited(NotificationService().onUserSignedOut());
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _handleSignedIn(sb.User user) async {
    _currentUser = user;
    _pendingEmail = null;
    _accountDisabled = false;

    await _loadOnboardingStatus();

    // Biometric lock only on cold start / resume with a persisted session,
    // not right after an explicit sign-in.
    final bioEnabled = await _storage.isBiometricEnabled();
    if (bioEnabled && !_justLoggedIn) {
      _isLocked = true;
    }
    // Must stay true while locked so GoRouter shows the lock screen.
    _isAuthenticated = true;
    _justLoggedIn = false;

    Map<String, dynamic>? profile;
    try {
      profile = await _db.getDocument(
        collectionId: AppConfig.usersCollection,
        documentId: user.id,
      );
      await _applyProfile(profile);

      // Self-heal: Auth confirmed the email/phone but the row lags behind.
      final authConfirmed =
          user.emailConfirmedAt != null || user.phoneConfirmedAt != null;
      if (authConfirmed && !_isVerified) {
        try {
          await _db.updateDocument(
            collectionId: AppConfig.usersCollection,
            documentId: user.id,
            data: {'isVerified': true},
          );
          _isVerified = true;
        } on Exception catch (e) {
          developer.log('Failed to sync verification: $e');
        }
      }
    } on Exception catch (e) {
      developer.log('Error fetching profile: $e', name: 'AuthProvider');
      final cachedRole = await _storage.getUserRole();
      if (cachedRole != null) _userRole = _parseUserRole(cachedRole);
    }

    if (_accountDisabled) {
      developer.log('Account is disabled — signing out', name: 'AuthProvider');
      await logout();
      return;
    }

    // Record a consent given during registration, now that a session exists.
    await _flushPendingNdpaConsent();

    _startProfileListener(user.id);

    _syncPushIdentity(user.id, profile);

    _phoneNumber = await _storage.getPhoneNumber();
    _isInitialized = true;
    notifyListeners();
  }

  /// Identifies this device to OneSignal with the user id and targeting
  /// tags. The role tag is the effective role (what the database grants).
  void _syncPushIdentity(String uid, Map<String, dynamic>? profile) {
    unawaited(
      NotificationService().onUserSignedIn(
        userId: uid,
        role: userRole?.dbValue,
        lga: profile?['lga'] as String?,
        state: profile?['state'] as String?,
        ward: profile?['ward'] as String?,
        monitoringZone: profile?['monitoringZone'] as String?,
      ),
    );
  }

  /// Applies role / approval / verification / disabled flags from a
  /// profile row. Returns true when anything changed.
  Future<bool> _applyProfile(Map<String, dynamic> data) async {
    var changed = false;
    final roleStr = data['role'] as String?;
    if (roleStr != null) {
      final role = _parseUserRole(roleStr);
      if (role != _userRole) {
        _userRole = role;
        changed = true;
      }
      await _storage.saveUserRole(roleStr);
    }
    final approved = data['isApproved'] as bool? ?? false;
    final verified = data['isVerified'] as bool? ?? false;
    if (_isApproved != approved) {
      _isApproved = approved;
      changed = true;
    }
    if (_isVerified != verified) {
      _isVerified = verified;
      changed = true;
    }
    final disabled = data['isDisabled'] as bool? ?? false;
    if (_accountDisabled != disabled) {
      _accountDisabled = disabled;
      changed = true;
    }
    final ward = data['ward'] as String?;
    if (_ward != ward) {
      _ward = ward;
      changed = true;
    }
    return changed;
  }

  Future<void> _loadOnboardingStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hasCompletedOnboarding =
          prefs.getBool('has_completed_onboarding') ?? false;
    } on Exception catch (e) {
      developer.log('Failed to load onboarding status: $e');
    }
  }

  /// Realtime subscription on the user's own profile row, so admin changes
  /// to role / approval / disabled take effect immediately.
  void _startProfileListener(String uid) {
    _profileSub?.cancel();
    _profileSub = _db
        .subscribeToDocument(
          collectionId: AppConfig.usersCollection,
          documentId: uid,
        )
        .listen(
          (data) async {
            if (data == null) return;
            final changed = await _applyProfile(data);
            if (_accountDisabled) {
              developer.log(
                'Account disabled via admin — logging out',
                name: 'AuthProvider',
              );
              await logout();
              return;
            }
            if (changed) {
              // Role / approval / ward changed: refresh push targeting.
              _syncPushIdentity(uid, data);
              notifyListeners();
            }
          },
          onError: (Object e) {
            developer.log('Profile listener error: $e', name: 'AuthProvider');
          },
        );
  }

  /// Force reload of user data (e.g. after profile update or verification).
  Future<void> reloadUserData() async {
    try {
      final user = await _db.reloadCurrentUser();
      if (user == null) return;
      _currentUser = user;
      final profile = await _db.getDocument(
        collectionId: AppConfig.usersCollection,
        documentId: user.id,
      );
      await _applyProfile(profile);
      notifyListeners();
    } on Exception catch (e) {
      developer.log('reloadUserData failed: $e', name: 'AuthProvider');
    }
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

  /// Creates the account. With email confirmation enabled (recommended),
  /// Supabase emails a 6-digit code and no session exists until
  /// [verifyOtpAndLogin] succeeds.
  ///
  /// [ndpaPolicyVersion] records the NDPA consent once a session exists.
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    String? name,
    String? address,
    UserRole? role,
    String? state,
    String? lga,
    String? ward,
    String? phoneNumber,
    String? ndpaPolicyVersion,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Sign out any stale session
      if (_db.getCurrentUser() != null) await _db.logout();

      final normalisedEmail = email.trim().toLowerCase();
      if (ndpaPolicyVersion != null) {
        _pendingNdpaConsent = {'policyVersion': ndpaPolicyVersion};
      }

      _justLoggedIn = true;
      final response = await _db.auth.signUp(
        email: normalisedEmail,
        password: password,
        data: _signUpMetadata(
          name: name,
          role: role,
          phone: phoneNumber,
          state: state,
          lga: lga,
          ward: ward,
          address: address,
        ),
      );

      // With confirmations on, an already-registered address returns an
      // obfuscated user without identities instead of an error.
      final identities = response.user?.identities;
      if (response.session == null &&
          identities != null &&
          identities.isEmpty) {
        _justLoggedIn = false;
        throw AuthException('Email is already registered. Please login.');
      }

      if (response.session == null) {
        // Waiting for the emailed code.
        _justLoggedIn = false;
        _pendingEmail = normalisedEmail;
      } else {
        await _ensureSignedIn(response.session!.user);
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException {
      _isLoading = false;
      notifyListeners();
      rethrow;
    } on sb.AuthException catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      developer.log(
        'SignUp AuthException: ${e.code} – ${e.message}',
        name: 'AuthProvider',
      );
      throw _mapSignUpError(e);
    } on Exception catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.signUpWithEmail');
      throw AuthException('Registration failed. Please try again.');
    }
  }

  AuthException _mapSignUpError(sb.AuthException e) {
    if (e is sb.AuthRetryableFetchException) {
      return AuthException(
        'Network error. Please check your connection and try again.',
      );
    }
    if (e is sb.AuthWeakPasswordException || e.code == 'weak_password') {
      return AuthException(
        'Password is too weak. Use at least 8 characters with letters, numbers and symbols.',
      );
    }
    switch (e.code) {
      case 'user_already_exists':
      case 'email_exists':
      case 'phone_exists':
        return AuthException(
          'This account is already registered. Please login.',
        );
      case 'email_address_invalid':
      case 'validation_failed':
        return AuthException('Please enter a valid email address.');
      case 'signup_disabled':
      case 'email_provider_disabled':
      case 'phone_provider_disabled':
        return AuthException(
          'Registration is currently disabled. Please contact support.',
        );
      case 'over_email_send_rate_limit':
      case 'over_sms_send_rate_limit':
      case 'over_request_rate_limit':
        return AuthException(
          'Too many attempts. Please wait a few minutes before trying again.',
        );
      default:
        return AuthException('Registration failed. Please try again.');
    }
  }

  Map<String, dynamic> _signUpMetadata({
    String? name,
    UserRole? role,
    String? phone,
    String? state,
    String? lga,
    String? ward,
    String? address,
  }) => {
    'name': name ?? 'User',
    // Requested role only; it grants nothing until an admin approves.
    'role': (role ?? UserRole.user).dbValue,
    'phone': phone ?? '',
    'state': state ?? '',
    'lga': lga ?? '',
    'ward': ward ?? '',
    'address': address ?? '',
  };

  // ─────────────────────────── Sign In ─────────────────────────────────────

  Future<bool> signInWithEmail({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    final normalisedEmail = email.trim().toLowerCase();
    try {
      _isLoading = true;
      notifyListeners();

      final rateLimitResult = await _rateLimiter.checkLoginAttempt();
      if (!rateLimitResult.allowed) {
        throw AuthException(rateLimitResult.userMessage);
      }

      // Clear stale state
      if (_db.getCurrentUser() != null) await _db.logout();
      _currentUser = null;
      _isAuthenticated = false;
      _userRole = null;

      final deviceFingerprint = await _fingerprintService.generateFingerprint();
      final deviceName = await _fingerprintService.getDeviceName();

      _justLoggedIn = true;
      final response = await _db.auth.signInWithPassword(
        email: normalisedEmail,
        password: password,
      );
      final user = response.user ?? response.session?.user;
      if (user == null) throw AuthException('Login failed. Please try again.');

      await _ensureSignedIn(user);
      if (_accountDisabled || _currentUser == null) {
        throw AuthException(
          'This account has been disabled. Please contact support.',
        );
      }

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

      unawaited(_touchLastLogin(user.id));
      await _startUserSession(
        user,
        _userRole ?? UserRole.user,
        rememberMe: rememberMe,
      );
      await _rateLimiter.resetLoginAttempts();

      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      rethrow;
    } on sb.AuthException catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      developer.log(
        'Login AuthException: ${e.code} – ${e.message}',
        name: 'AuthProvider',
      );
      if (e is sb.AuthRetryableFetchException) {
        throw AuthException('Login failed. Please check your connection.');
      }
      switch (e.code) {
        case 'invalid_credentials':
        case 'user_not_found':
          await _rateLimiter.recordFailedLogin();
          throw AuthException('Invalid email or password');
        case 'email_not_confirmed':
          _pendingEmail = normalisedEmail;
          try {
            await _resendSignupCode(normalisedEmail);
          } on Exception catch (resendError) {
            developer.log('Resend failed: $resendError', name: 'AuthProvider');
          }
          throw EmailNotConfirmedException(normalisedEmail);
        case 'user_banned':
          throw AuthException(
            'This account has been disabled. Please contact support.',
          );
        case 'over_request_rate_limit':
          throw AuthException(
            'Too many login attempts. Please wait a few minutes and try again.',
          );
        default:
          ErrorHandler.logError(
            'Unhandled AuthException: ${e.code} – ${e.message}',
            context: 'AuthProvider.signInWithEmail',
          );
          throw AuthException('Login failed. Please try again.');
      }
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

  Future<void> _touchLastLogin(String uid) async {
    try {
      await _db.updateDocument(
        collectionId: AppConfig.usersCollection,
        documentId: uid,
        data: {'lastLoginAt': DateTime.now()},
      );
    } on Exception catch (e) {
      developer.log('lastLoginAt update failed: $e', name: 'AuthProvider');
    }
  }

  // ─────────────────────────── OTP ─────────────────────────────────────────

  /// Sends a Supabase SMS OTP to [phone].
  ///
  /// Pass [registrationData] (name, address, role, state, lga, ward) when
  /// registering: it becomes the new user's metadata, from which the
  /// database creates the profile. Without it only existing accounts (or a
  /// registration started earlier in this session) can sign in.
  Future<bool> sendOtpForPhone(
    String phone, {
    Map<String, dynamic>? registrationData,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      final rateLimitResult = await _rateLimiter.checkOtpResend();
      if (!rateLimitResult.allowed) {
        throw AuthException(rateLimitResult.userMessage);
      }

      final normalised = Validators.normalizePhoneNumber(phone.trim());
      if (normalised.length < 8) {
        throw AuthException('Invalid phone number.');
      }

      if (registrationData != null) {
        _pendingPhoneMetadata = _signUpMetadata(
          name: registrationData['name'] as String?,
          role: registrationData['role'] as UserRole?,
          phone: normalised,
          state: registrationData['state'] as String?,
          lga: registrationData['lga'] as String?,
          ward: registrationData['ward'] as String?,
          address: registrationData['address'] as String?,
        );
        final version = registrationData['ndpaPolicyVersion'] as String?;
        if (version != null) {
          _pendingNdpaConsent = {'policyVersion': version};
        }
      }

      await _db.auth.signInWithOtp(
        phone: normalised,
        shouldCreateUser: _pendingPhoneMetadata != null,
        data: _pendingPhoneMetadata,
      );
      await _storage.savePhoneNumber(normalised);
      await _rateLimiter.recordOtpResend();

      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException {
      _isLoading = false;
      notifyListeners();
      rethrow;
    } on sb.AuthException catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Phone OTP error: ${e.code} ${e.message}');
      switch (e.code) {
        case 'phone_provider_disabled':
        case 'sms_send_failed':
          throw AuthException(
            'SMS service is not available. Please contact support.',
          );
        case 'otp_disabled':
          throw AuthException(
            'No account found for this number. Please register first.',
          );
        case 'over_sms_send_rate_limit':
        case 'over_request_rate_limit':
          throw AuthException(
            'Too many attempts. Please wait a few minutes before trying again.',
          );
        default:
          throw AuthException('Failed to send verification SMS.');
      }
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.sendOtpForPhone');
      throw AuthException('Failed to send verification SMS.');
    }
  }

  /// Re-sends the sign-up confirmation code to [email].
  Future<bool> sendOtpForEmail(String email, {String? name}) async {
    try {
      _isLoading = true;
      notifyListeners();

      final rateLimitResult = await _rateLimiter.checkOtpResend();
      if (!rateLimitResult.allowed) {
        throw AuthException(rateLimitResult.userMessage);
      }

      await _resendSignupCode(email.trim().toLowerCase());
      await _rateLimiter.recordOtpResend();

      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException {
      _isLoading = false;
      notifyListeners();
      rethrow;
    } on sb.AuthException catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Resend error: ${e.code} ${e.message}');
      if (e.code == 'over_email_send_rate_limit' ||
          e.code == 'over_request_rate_limit') {
        throw AuthException(
          'Too many attempts. Please wait a few minutes before trying again.',
        );
      }
      throw AuthException('Failed to send verification code.');
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.sendOtpForEmail');
      throw AuthException('Failed to send verification code.');
    }
  }

  Future<void> _resendSignupCode(String email) =>
      _db.auth.resend(type: sb.OtpType.signup, email: email);

  /// Verifies a 6-digit code: the email sign-up confirmation code, or the
  /// SMS code for phone sign-in/registration. On success a session exists
  /// and the user is signed in.
  Future<bool> verifyOtpAndLogin(
    String otp, {
    Map<String, dynamic>? registrationData,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      var data = registrationData;
      if (data == null ||
          (!data.containsKey('email') && !data.containsKey('phone'))) {
        final email = pendingEmail;
        if (email == null || email.isEmpty) {
          throw AuthException(
            'No user context for verification. Please login again.',
          );
        }
        data = {'email': email};
      }

      final isPhoneFlow =
          data.containsKey('phone') && !data.containsKey('email');
      final token = otp.trim();

      _justLoggedIn = true;
      final sb.AuthResponse response;
      if (isPhoneFlow) {
        response = await _db.auth.verifyOTP(
          type: sb.OtpType.sms,
          phone: Validators.normalizePhoneNumber(data['phone'] as String),
          token: token,
        );
      } else {
        response = await _db.auth.verifyOTP(
          type: sb.OtpType.signup,
          email: (data['email'] as String).trim().toLowerCase(),
          token: token,
        );
      }

      final user = response.user ?? response.session?.user;
      if (user == null) {
        throw AuthException('Verification failed. Please try again.');
      }
      _pendingPhoneMetadata = null;
      await _ensureSignedIn(user);
      if (_accountDisabled) {
        throw AuthException(
          'This account has been disabled. Please contact support.',
        );
      }
      _isVerified = true;
      await _startUserSession(user, _userRole ?? UserRole.user);

      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      rethrow;
    } on sb.AuthException catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      developer.log(
        'verifyOtp AuthException: ${e.code} – ${e.message}',
        name: 'AuthProvider',
      );
      if (e is sb.AuthRetryableFetchException) {
        throw AuthException('Network error. Please check your connection.');
      }
      if (e.code == 'otp_expired' || e.code == 'invalid_credentials') {
        throw AuthException(
          'Invalid or expired verification code. Please request a new one.',
        );
      }
      if (e.code == 'over_request_rate_limit') {
        throw AuthException(
          'Too many attempts. Please wait a few minutes and try again.',
        );
      }
      throw AuthException('Verification failed. Please try again.');
    } on Exception catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.verifyOtpAndLogin');
      throw AuthException('Failed to verify code.');
    }
  }

  Future<void> resendVerificationLink() async {
    final email = pendingEmail;
    if (email == null || email.isEmpty) {
      throw AuthException('User not logged in');
    }
    try {
      await sendOtpForEmail(email);
    } on AuthException {
      rethrow;
    } on Exception catch (_) {
      throw AuthException(
        'Failed to resend verification code. Please try again.',
      );
    }
  }

  // ─────────────────────────── NDPA consent ────────────────────────────────

  Future<void> _flushPendingNdpaConsent() async {
    final consent = _pendingNdpaConsent;
    if (consent == null) return;
    try {
      await _db.upsertDocument(
        collectionId: AppConfig.ndpaConsentsCollection,
        ignoreDuplicates: true,
        data: {
          'policyVersion': consent['policyVersion'],
          'dataResidency': 'supabase',
          'platform': 'mobile',
          'method': 'registration_screen',
        },
      );
      _pendingNdpaConsent = null;
      developer.log('NDPA consent recorded', name: 'AuthProvider');
    } on Exception catch (e) {
      // Non-fatal: retried on the next sign-in of this app session.
      developer.log('NDPA consent record failed: $e', name: 'AuthProvider');
    }
  }

  // ─────────────────────────── Password Reset ───────────────────────────────

  /// Sends a recovery email containing a 6-digit code.
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      _isLoading = true;
      notifyListeners();
      await _db.auth.resetPasswordForEmail(email.trim().toLowerCase());
      _isLoading = false;
      notifyListeners();
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.sendPasswordResetEmail');
      throw AuthException('Failed to send reset email. Please try again.');
    }
  }

  /// Completes a password reset with the recovery [code] emailed to
  /// [email]. The temporary recovery session is signed out afterwards so the
  /// user logs in with the new password.
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      _isLoading = true;
      _recovering = true;
      notifyListeners();
      await _db.auth.verifyOTP(
        type: sb.OtpType.recovery,
        email: email.trim().toLowerCase(),
        token: code.trim(),
      );
      await _db.auth.updateUser(sb.UserAttributes(password: newPassword));
    } on sb.AuthException catch (e) {
      ErrorHandler.logError(e, context: 'AuthProvider.confirmPasswordReset');
      if (e is sb.AuthWeakPasswordException || e.code == 'weak_password') {
        throw AuthException('Password is too weak. Please choose another.');
      }
      switch (e.code) {
        case 'otp_expired':
        case 'invalid_credentials':
          throw AuthException(
            'This reset code is invalid or has expired. Please request a new one.',
          );
        case 'same_password':
          throw AuthException(
            'Your new password must be different from the old one.',
          );
        default:
          throw AuthException('Failed to reset password. Please try again.');
      }
    } on Exception catch (e) {
      ErrorHandler.logError(e, context: 'AuthProvider.confirmPasswordReset');
      throw AuthException('Failed to reset password. Please try again.');
    } finally {
      try {
        if (_db.getCurrentUser() != null) await _db.logout();
      } on Exception catch (_) {}
      _recovering = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─────────────────────────── Biometrics ──────────────────────────────────

  /// Unlocks with biometrics using the persisted Supabase session. Returns
  /// false when there is no usable session (the user must sign in with
  /// their password).
  Future<bool> authenticateWithBiometrics() async {
    try {
      final isBiometricEnabled = await _storage.isBiometricEnabled();
      if (!isBiometricEnabled) return false;

      final authenticated = await _biometricService.authenticateForLogin();
      if (!authenticated) return false;

      final isValid = await _isServerSessionValid();
      if (!isValid) return false;

      final user = _db.getCurrentUser();
      if (user == null) return false;

      _justLoggedIn = true;
      await _ensureSignedIn(user);
      _justLoggedIn = false;
      _isLocked = false;
      _isAuthenticated = _currentUser != null;
      _phoneNumber = await _storage.getPhoneNumber();
      notifyListeners();
      return _isAuthenticated;
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
      if (!canAuth) throw AuthException('Biometric authentication failed');
    }
    await _storage.setBiometricEnabled(enabled);
    final user = _db.getCurrentUser();
    if (user != null) {
      try {
        await _db.updateDocument(
          collectionId: AppConfig.usersCollection,
          documentId: user.id,
          data: {'biometricsEnabled': enabled},
        );
      } on Exception catch (e) {
        developer.log('Error syncing biometric setting: $e');
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
    if (!SupabaseService.isReady) return false;
    final session = _db.auth.currentSession;
    if (session == null) {
      developer.log('No persisted session.', name: 'AuthProvider');
      return false;
    }
    try {
      if (session.isExpired) {
        await _db.auth.refreshSession();
      }
      await _sessionManager.extendSession();
      return true;
    } on sb.AuthRetryableFetchException catch (e) {
      // Offline — allow access with the cached session.
      developer.log('Session refresh offline: $e', name: 'AuthProvider');
      return true;
    } on sb.AuthException catch (e) {
      developer.log('Session invalid: ${e.code}', name: 'AuthProvider');
      await logout();
      return false;
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

      await _profileSub?.cancel();
      _profileSub = null;

      try {
        await _sessionManager.logout();
      } on Exception catch (e) {
        developer.log('Session manager logout error: $e', name: 'AuthProvider');
      }

      await NotificationService().onUserSignedOut();

      // Revokes the refresh token and clears the persisted session.
      await _db.logout();

      await _storage.clearAll(keepPreferences: true);

      _signInFuture = null;
      _signInUid = null;
      _isAuthenticated = false;
      _isLocked = false;
      _userRole = null;
      _currentUser = null;
      _phoneNumber = null;
      _isApproved = null;
      _isVerified = false;
      _ward = null;
      _accountDisabled = false;
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

  Future<void> _startUserSession(
    sb.User user,
    UserRole role, {
    bool rememberMe = false,
  }) async {
    await _storage.saveUserRole(role.dbValue);
    await _sessionManager.startSession(
      authToken: user.id,
      userRole: role.dbValue,
      rememberMe: rememberMe,
    );
    _isAuthenticated = true;
  }

  UserRole? _parseUserRole(String? roleStr) => UserRoleValue.fromDb(roleStr);

  @override
  void dispose() {
    _authSub.cancel();
    _profileSub?.cancel();
    _sessionManager.dispose();
    super.dispose();
  }
}
