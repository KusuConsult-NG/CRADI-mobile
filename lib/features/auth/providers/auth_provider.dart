import 'dart:async';
import 'dart:developer' as developer;
import 'package:climate_app/core/utils/error_handler.dart';
export 'package:climate_app/core/utils/error_handler.dart'
    show AuthException, EmailNotConfirmedException;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:climate_app/core/services/auth_backend.dart';
import 'package:climate_app/core/services/supabase_auth_backend.dart';
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
import 'package:climate_app/core/l10n/l10n.dart';

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

  /// Display name of the role in the language of [l10n] (the stored value
  /// is [dbValue]).
  String label(AppLocalizations l10n) => switch (this) {
    UserRole.user => l10n.roleUser,
    UserRole.ewm => l10n.roleEwm,
    UserRole.ewv => l10n.roleEwv,
    UserRole.ewr => l10n.roleEwr,
    UserRole.ldpCoordinator => l10n.roleLdpCoordinator,
    UserRole.projectStaff => l10n.roleProjectStaff,
    UserRole.admin => l10n.roleAdmin,
    UserRole.techSupport => l10n.roleTechSupport,
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

/// Authentication state and operations — backed by an [AuthBackend] and the
/// `profiles` table.
///
/// * Sign-up passes the profile fields as account metadata; the backend
///   creates the `profiles` row. The client never inserts it.
/// * Email verification and password recovery use 6-digit codes.
/// * Phone accounts use SMS one-time codes.
/// * The session (incl. refresh token) is persisted by the backend adapter
///   in secure storage; the biometric lock re-uses it — no password is
///   stored.
/// * Role / approval / disabled changes arrive through a realtime
///   subscription on the user's own profile row.
///
/// Nothing below names a vendor. The backend's own error codes are
/// translated to [AuthFailure] by the adapter, which is the only file that
/// knows them; the flows here choose the wording, because the same
/// condition reads differently during registration and during a password
/// reset.
class AuthProvider extends ChangeNotifier {
  /// [auth] is injectable so tests can drive the flows without a server;
  /// it defaults to the Supabase adapter.
  AuthProvider({AuthBackend? auth}) : _auth = auth ?? SupabaseAuthBackend() {
    _initializeSessionManager();
    unawaited(_storage.purgeLegacyCredentials());
    _authSub = _auth.changes.listen(
      _onAuthEvent,
      onError: (Object e) =>
          developer.log('Auth stream error: $e', name: 'AuthProvider'),
    );
    if (!_auth.isConfigured) {
      // No backend configured: behave as signed out.
      unawaited(_handleSignedOut());
    } else {
      // The auth stream only replays its latest event: when the session
      // restored at startup was already refreshed, only `tokenRefreshed`
      // arrives. Seed the state from the restored session instead of
      // waiting for `initialSession`.
      final restored = _auth.currentUser;
      if (restored != null) {
        unawaited(_ensureSignedIn(restored));
      } else {
        unawaited(_handleSignedOut());
      }
    }
    // Safety net: never leave the app stuck on the splash screen.
    _initTimer = Timer(initTimeout, _onInitTimeout);
  }

  /// How long the splash screen may wait for the initial auth state.
  static const Duration initTimeout = Duration(seconds: 12);

  /// Phone (SMS OTP) sign-up and sign-in. Keep false until an SMS provider
  /// is configured on the backend; the registration and login screens hide
  /// the phone option meanwhile.
  static const bool phoneAuthEnabled = false;

  final AuthBackend _auth;
  final SupabaseService _db = SupabaseService();
  bool _isAuthenticated = false;
  UserRole? _userRole;
  String? _phoneNumber;
  bool _isLoading = false;
  AuthUser? _currentUser;
  bool? _isApproved;
  bool _isVerified = false;
  String? _ward;
  String? _lga;
  Timer? _initTimer;

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
  // True for the length of [confirmPasswordReset] (verifyOTP recovery →
  // updateUser → signOut); auth events are ignored meanwhile. Only that
  // method sets it, so it can never stay raised past the reset.
  bool _recovering = false;
  // Set when a recovery link is opened in the app: the session that arrives
  // with it is valid, but the user still has to choose a new password before
  // anything else. Cleared by [completePasswordRecovery] / [logout].
  bool _passwordRecoveryPending = false;
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
  late final StreamSubscription<AuthChange> _authSub;

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

  /// Roles that may send a verification request (/verification/request).
  /// The only entry point is the verification list, which is limited to
  /// [verifierRoles], so this must stay a subset of those.
  static const Set<UserRole> verificationRequestRoles = {
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

  /// Roles that may read the peer votes (and dispute comments) on reports
  /// (`verifications_select`).
  static const Set<UserRole> verificationReaderRoles = {
    UserRole.ewm,
    UserRole.ewv,
    UserRole.ewr,
    UserRole.ldpCoordinator,
    UserRole.projectStaff,
    UserRole.admin,
    UserRole.techSupport,
  };

  /// Roles that may broadcast / dismiss alerts (`alerts_insert` /
  /// `alerts_update`).
  static const Set<UserRole> alertManagerRoles = {
    UserRole.ewv,
    UserRole.ewr,
    UserRole.ldpCoordinator,
    UserRole.projectStaff,
    UserRole.admin,
    UserRole.techSupport,
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

  /// The signed-in user's LGA (from the profile row).
  String? get lga => _lga;

  /// Whether the user may cast a peer-verification vote on a report (mirrors
  /// the `verifications_insert` policy): never on one's own report, and an
  /// EWM only within their own LGA *and* ward (ward names repeat across
  /// LGAs, so the ward alone is not enough).
  bool canVoteOn({String? reporterId, String? reportWard, String? reportLga}) {
    final role = userRole;
    if (role == null || !verifierRoles.contains(role)) return false;
    final uid = _currentUser?.id;
    if (reporterId != null && uid != null && reporterId == uid) return false;
    if (role == UserRole.ewm) {
      return _sameArea(_ward, reportWard) && _sameArea(_lga, reportLga);
    }
    return true;
  }

  // Exact match, like the database policy (values come from the same
  // location lists), so the button never shows for a vote the DB refuses.
  static bool _sameArea(String? mine, String? theirs) {
    final a = mine ?? '';
    return a.isNotEmpty && a == theirs;
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
  AuthUser? get currentUser => _currentUser;
  bool? get isApproved => _isApproved;
  bool get isVerified => _isVerified;
  bool get isInitialized => _isInitialized;
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;
  bool get isLocked => _isLocked;

  /// True between opening a recovery link and setting the new password.
  /// The router parks the app on the reset screen while it holds.
  bool get isPasswordRecoveryPending => _passwordRecoveryPending;

  /// Email of the account waiting for OTP confirmation, if any.
  String? get pendingEmail => _pendingEmail ?? _currentUser?.email;

  /// Whether a persisted session exists on this device (the biometric
  /// sign-in re-uses it; after a logout there is none).
  bool get hasStoredSession => _auth.hasSession;

  /// Called after every completed sign-in (new user id) — e.g. to refetch
  /// data that was loaded before the session existed.
  final List<VoidCallback> _signInListeners = [];
  void addSignInListener(VoidCallback listener) =>
      _signInListeners.add(listener);
  void removeSignInListener(VoidCallback listener) =>
      _signInListeners.remove(listener);

  /// Called after the user state was cleared on sign-out (including a
  /// signed-out cold start) — e.g. to drop caches of the previous account.
  final List<VoidCallback> _signOutListeners = [];
  void addSignOutListener(VoidCallback listener) =>
      _signOutListeners.add(listener);
  void removeSignOutListener(VoidCallback listener) =>
      _signOutListeners.remove(listener);

  /// Incremented whenever the user state is reset or a new sign-in starts;
  /// an in-flight [_handleSignedIn] stops once it no longer matches.
  int _authGen = 0;

  /// User id the sign-in listeners last ran for (null after a reset), so a
  /// sign-in that is retried after a failed attempt still notifies them.
  String? _listenersFiredFor;

  static void _notifyAll(List<VoidCallback> listeners, String kind) {
    for (final listener in List.of(listeners)) {
      try {
        listener();
      } on Exception catch (e) {
        developer.log('$kind listener error: $e', name: 'AuthProvider');
      }
    }
  }

  // ─────────────────────────── Initialization ───────────────────────────────

  void _onInitTimeout() {
    if (_isInitialized) return;
    developer.log(
      'Auth initialization timed out — leaving the splash screen',
      name: 'AuthProvider',
    );
    _isInitialized = true;
    notifyListeners();
  }

  void _initializeSessionManager() {
    // Inactivity timeout: lock (keeping the session) when biometrics are
    // enabled, otherwise sign out.
    _sessionManager.onSessionExpired = () async {
      if (!_isAuthenticated) return;
      final bioEnabled = await _storage.isBiometricEnabled(
        forUserId: _currentUser?.id,
      );
      if (bioEnabled) {
        _isLocked = true;
        notifyListeners();
      } else {
        await logout();
      }
    };
  }

  Future<void> _onAuthEvent(AuthChange change) async {
    final user = change.user;
    switch (change.event) {
      case AuthEvent.passwordRecovery:
        // [_recovering] is raised by [confirmPasswordReset] for the length
        // of the reset; the event it triggers is ignored there.
        if (_recovering) return;
        // An unsolicited recovery session (a recovery link opened in the
        // app rather than a code typed on the reset screen) is a perfectly
        // valid session. Treat it as a sign-in: latching [_recovering]
        // here would make the provider ignore every later auth event —
        // token refreshes and the initial session included — for the rest
        // of the app's life.
        if (user == null) {
          await _handleSignedOut();
          return;
        }
        // Raised *after* the sign-in: _ensureSignedIn may sign a stale
        // session out first, and that clears the flag again.
        await _ensureSignedIn(user);
        _passwordRecoveryPending = true;
        notifyListeners();
        return;
      case AuthEvent.signedOut:
        await _handleSignedOut();
        return;
      case AuthEvent.initialSession:
      case AuthEvent.signedIn:
        if (_recovering) return;
        if (user == null) {
          await _handleSignedOut();
          return;
        }
        await _ensureSignedIn(user);
        return;
      case AuthEvent.tokenRefreshed:
      case AuthEvent.userUpdated:
      case AuthEvent.other:
        if (user == null || _recovering) return;
        if (_signInUid != user.id) {
          // Not signed in for this user yet: the stream only replays its
          // latest event, so a refresh that completed before we subscribed
          // is the only event we get. Treat it as a sign-in.
          await _ensureSignedIn(user);
          return;
        }
        // Keep the user object fresh without re-running the sign-in flow
        // (which would re-lock the app).
        _currentUser = user;
        if (change.event == AuthEvent.userUpdated) {
          notifyListeners();
        }
    }
  }

  Future<void> _ensureSignedIn(AuthUser user) {
    final inFlight = _signInFuture;
    if (_signInUid == user.id && inFlight != null) return inFlight;
    _signInUid = user.id;
    // Supersede any sign-in still running for another user.
    final gen = ++_authGen;
    return _signInFuture = _handleSignedIn(user).catchError((
      Object e,
      StackTrace st,
    ) {
      // Do not cache a failed sign-in: a later auth event must retry it.
      if (gen == _authGen && _signInUid == user.id) {
        _signInFuture = null;
        _signInUid = null;
      }
      Error.throwWithStackTrace(e, st);
    });
  }

  Future<void> _handleSignedOut() async {
    // Sign-in paths sign out a stale session first; that `signedOut` event
    // can be delivered after the new sign-in completed. Ignore it while a
    // session exists.
    if (_auth.hasSession) {
      developer.log('Ignoring stale signedOut event', name: 'AuthProvider');
      return;
    }
    _passwordRecoveryPending = false;
    final profileSub = _profileSub;
    _profileSub = null;
    _resetUserState();
    // A sign-in that starts during the awaits below supersedes this run.
    final gen = _authGen;
    _sessionManager.cancelTimers();
    // Before any await, so a sign-in that follows is queued after it.
    unawaited(NotificationService().onUserSignedOut());
    await profileSub?.cancel();
    // Load onboarding status here too, otherwise logged-out users are sent
    // back to /onboarding on every cold start.
    await _loadOnboardingStatus();
    if (gen != _authGen) return;
    _isInitialized = true;
    notifyListeners();
    _notifyAll(_signOutListeners, 'Sign-out');
  }

  /// Clears everything tied to the signed-in user (logout / sign-out).
  /// Pending registration data (email / phone OTP in progress) is kept.
  void _resetUserState() {
    _authGen++;
    _listenersFiredFor = null;
    _signInFuture = null;
    _signInUid = null;
    _currentUser = null;
    _isAuthenticated = false;
    _isLocked = false;
    _userRole = null;
    _phoneNumber = null;
    _isApproved = null;
    _isVerified = false;
    _ward = null;
    _lga = null;
    _accountDisabled = false;
  }

  Future<void> _handleSignedIn(AuthUser user) async {
    // A sign-out (or another sign-in) during any await below cancels this
    // run: nothing may be applied for a user who is no longer signed in.
    final gen = _authGen;
    bool stale() => gen != _authGen;
    if (_currentUser != null && _currentUser!.id != user.id) {
      // A different account without an intervening sign-out: drop the
      // previous user's profile-derived state.
      _userRole = null;
      _isApproved = null;
      _isVerified = false;
      _ward = null;
      _lga = null;
      _phoneNumber = null;
    }
    _currentUser = user;
    _pendingEmail = null;
    _accountDisabled = false;
    // The auth server already knows whether the email / phone is
    // confirmed; do not send confirmed users to the verify screen when the
    // profile row cannot be fetched.
    if (user.isConfirmed) _isVerified = true;

    await _loadOnboardingStatus();
    if (stale()) return;

    // Biometric lock only on cold start / resume with a persisted session,
    // not right after an explicit sign-in.
    // The lock belongs to the account that enabled it: a flag left by
    // another account on this device is cleared.
    await _storage.bindBiometricOwner(user.id);
    if (stale()) return;
    final bioEnabled = await _storage.isBiometricEnabled(forUserId: user.id);
    if (stale()) return;
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
      if (stale()) return;
      await _applyProfile(profile);
      if (stale()) return;

      // Self-heal: Auth confirmed the email/phone but the row lags behind.
      if (user.isConfirmed && profile['isVerified'] != true) {
        try {
          await _db.updateDocument(
            collectionId: AppConfig.usersCollection,
            documentId: user.id,
            data: {'isVerified': true},
          );
        } on Exception catch (e) {
          developer.log('Failed to sync verification: $e');
        }
      }
    } on Exception catch (e) {
      developer.log('Error fetching profile: $e', name: 'AuthProvider');
      final cachedRole = await _storage.getUserRole();
      if (stale()) return;
      if (cachedRole != null) _userRole = _parseUserRole(cachedRole);
    }
    if (stale()) return;

    if (_accountDisabled) {
      developer.log('Account is disabled — signing out', name: 'AuthProvider');
      await logout();
      return;
    }

    // Record a consent given during registration, now that a session exists.
    await _flushPendingNdpaConsent();
    if (stale()) return;

    _startProfileListener(user.id);

    _syncPushIdentity(user.id, profile);

    final phone = await _storage.getPhoneNumber();
    if (stale()) return;
    _phoneNumber = phone;
    // (Re)start the inactivity timeout for this session.
    await _sessionManager.extendSession();
    if (stale()) return;
    _isInitialized = true;
    notifyListeners();
    if (_listenersFiredFor != user.id) {
      _listenersFiredFor = user.id;
      _notifyAll(_signInListeners, 'Sign-in');
    }
  }

  /// Identifies this device to OneSignal with the user id and targeting
  /// tags. The role tag is the effective role (what the database grants).
  /// Without a profile row (fetch failed) only the identity is synced: the
  /// role is unknown, and tagging it as `user` would drop staff targeting.
  void _syncPushIdentity(String uid, Map<String, dynamic>? profile) {
    unawaited(
      NotificationService().onUserSignedIn(
        userId: uid,
        role: userRole?.dbValue,
        lga: profile?['lga'] as String?,
        state: profile?['state'] as String?,
        ward: profile?['ward'] as String?,
        monitoringZone: profile?['monitoringZone'] as String?,
        updateTags: profile != null,
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
    final verified =
        (data['isVerified'] as bool? ?? false) ||
        (_currentUser?.isConfirmed ?? false);
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
    final lga = data['lga'] as String?;
    if (_lga != lga) {
      _lga = lga;
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
    // A missing row is only meaningful once the row has been seen: the
    // first snapshot may arrive before the profile exists (sign-up).
    var seenRow = false;
    _profileSub = _db
        .subscribeToDocument(
          collectionId: AppConfig.usersCollection,
          documentId: uid,
        )
        .listen(
          (data) async {
            if (data == null) {
              if (!seenRow || _currentUser?.id != uid) return;
              developer.log(
                'Profile row deleted — logging out',
                name: 'AuthProvider',
              );
              await logout(notice: (l) => l.authAccountRemoved);
              return;
            }
            seenRow = true;
            final changed = await _applyProfile(data);
            if (_accountDisabled) {
              developer.log(
                'Account disabled via admin — logging out',
                name: 'AuthProvider',
              );
              await logout(notice: (l) => l.authErrorAccountDisabled);
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
      final user = await _auth.reloadUser();
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

  /// [promptReason] is the localised text of the system biometric prompt.
  Future<bool> unlockApp({String? promptReason}) async {
    try {
      _isLoading = true;
      notifyListeners();

      final authenticated = await _biometricService.authenticateForLogin(
        reason: promptReason ?? englishL10n.biometricLoginPrompt,
      );

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
  /// the backend emails a 6-digit code and no session exists until
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
      if (_auth.currentUser != null) {
        await _auth.signOut();
        _resetUserState();
      }

      final normalisedEmail = email.trim().toLowerCase();
      if (ndpaPolicyVersion != null) {
        _pendingNdpaConsent = {'policyVersion': ndpaPolicyVersion};
      }

      _justLoggedIn = true;
      final outcome = await _auth.signUpWithPassword(
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

      final user = outcome.user;
      if (!outcome.hasSession || user == null) {
        // Waiting for the emailed code.
        _justLoggedIn = false;
        _pendingEmail = normalisedEmail;
      } else {
        await _ensureSignedIn(user);
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException {
      _isLoading = false;
      notifyListeners();
      rethrow;
    } on AuthBackendException catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      developer.log(
        'SignUp failure: ${e.failure.name} (${e.code} – ${e.message})',
        name: 'AuthProvider',
      );
      throw _mapSignUpError(e);
    } on Exception catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.signUpWithEmail');
      throw AuthException((l) => l.authErrorRegistrationFailed);
    }
  }

  AuthException _mapSignUpError(AuthBackendException e) => switch (e.failure) {
    AuthFailure.network => AuthException((l) => l.authErrorNetworkRetry),
    AuthFailure.weakPassword => AuthException((l) => l.authErrorWeakPassword),
    AuthFailure.accountExists => AuthException(
      (l) => l.authErrorAccountRegistered,
    ),
    AuthFailure.invalidEmail => AuthException((l) => l.validation_invalidEmail),
    AuthFailure.providerDisabled => AuthException(
      (l) => l.authErrorRegistrationDisabled,
    ),
    AuthFailure.rateLimited => AuthException((l) => l.authErrorTooManyAttempts),
    _ => AuthException((l) => l.authErrorRegistrationFailed),
  };

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

      // Clear stale state. The `signedOut` event of this logout may arrive
      // after the new session exists (and is then ignored), so reset the
      // previous user's state here.
      if (_auth.currentUser != null) await _auth.signOut();
      _resetUserState();

      final deviceFingerprint = await _fingerprintService.generateFingerprint();
      final deviceName = await _fingerprintService.getDeviceName();

      _justLoggedIn = true;
      final outcome = await _auth.signInWithPassword(
        email: normalisedEmail,
        password: password,
      );
      final user = outcome.user;
      if (user == null) throw AuthException((l) => l.authErrorLoginFailed);

      await _ensureSignedIn(user);
      if (_accountDisabled || _currentUser == null) {
        throw AuthException((l) => l.authErrorAccountDisabled);
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
    } on AuthBackendException catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      developer.log(
        'Login failure: ${e.failure.name} (${e.code} – ${e.message})',
        name: 'AuthProvider',
      );
      switch (e.failure) {
        case AuthFailure.network:
          throw AuthException((l) => l.authErrorLoginConnection);
        case AuthFailure.invalidCredentials:
          await _rateLimiter.recordFailedLogin();
          throw AuthException((l) => l.authErrorInvalidCredentials);
        case AuthFailure.emailNotConfirmed:
          _pendingEmail = normalisedEmail;
          try {
            await _resendSignupCode(normalisedEmail);
          } on Exception catch (resendError) {
            developer.log('Resend failed: $resendError', name: 'AuthProvider');
          }
          throw EmailNotConfirmedException(normalisedEmail);
        case AuthFailure.accountBanned:
          throw AuthException((l) => l.authErrorAccountDisabled);
        case AuthFailure.rateLimited:
          throw AuthException((l) => l.authErrorTooManyLogins);
        default:
          ErrorHandler.logError(
            'Unhandled auth failure: ${e.failure.name} '
            '(${e.code} – ${e.message})',
            context: 'AuthProvider.signInWithEmail',
          );
          throw AuthException((l) => l.authErrorLoginFailed);
      }
    } on Exception catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.signInWithEmail');
      if (kDebugMode) {
        // Debug builds only: raw diagnostics for developers (not
        // translated on purpose).
        final detail =
            'Login error: ${e.runtimeType} – ${e.toString().substring(0, e.toString().length.clamp(0, 200))}';
        throw AuthException((_) => detail);
      }
      throw AuthException((l) => l.authErrorLoginUnexpected);
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

  /// Sends an SMS one-time code to [phone].
  ///
  /// Pass [registrationData] (name, address, role, state, lga, ward) when
  /// registering: it becomes the new user's metadata, from which the
  /// database creates the profile. Without it only existing accounts (or a
  /// registration started earlier in this session) can sign in.
  ///
  /// With [loginOnly] (sign-in from the login screen) no account is ever
  /// created: an unknown number is rejected.
  Future<bool> sendOtpForPhone(
    String phone, {
    Map<String, dynamic>? registrationData,
    bool loginOnly = false,
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
        throw AuthException((l) => l.authErrorInvalidPhone);
      }

      if (loginOnly) {
        _pendingPhoneMetadata = null;
      } else if (registrationData != null) {
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

      await _auth.sendPhoneOtp(
        phone: normalised,
        createUser: _pendingPhoneMetadata != null,
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
    } on AuthBackendException catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Phone OTP failure: ${e.failure.name} ${e.message}');
      switch (e.failure) {
        case AuthFailure.providerDisabled:
        case AuthFailure.deliveryFailed:
          throw AuthException((l) => l.authErrorSmsUnavailable);
        case AuthFailure.otpDisabled:
          throw AuthException((l) => l.authErrorPhoneNotRegistered);
        case AuthFailure.rateLimited:
          throw AuthException((l) => l.authErrorTooManyAttempts);
        default:
          throw AuthException((l) => l.authErrorSmsFailed);
      }
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.sendOtpForPhone');
      throw AuthException((l) => l.authErrorSmsFailed);
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
    } on AuthBackendException catch (e) {
      _isLoading = false;
      notifyListeners();
      developer.log('Resend failure: ${e.failure.name} ${e.message}');
      if (e.failure == AuthFailure.rateLimited) {
        throw AuthException((l) => l.authErrorTooManyAttempts);
      }
      throw AuthException((l) => l.authErrorCodeSendFailed);
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.sendOtpForEmail');
      throw AuthException((l) => l.authErrorCodeSendFailed);
    }
  }

  Future<void> _resendSignupCode(String email) => _auth.resendSignUpCode(email);

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
          throw AuthException((l) => l.authErrorNoUserContext);
        }
        data = {'email': email};
      }

      final isPhoneFlow =
          data.containsKey('phone') && !data.containsKey('email');
      final token = otp.trim();

      _justLoggedIn = true;
      final AuthOutcome outcome;
      if (isPhoneFlow) {
        outcome = await _auth.verifyPhoneOtp(
          phone: Validators.normalizePhoneNumber(data['phone'] as String),
          token: token,
        );
      } else {
        outcome = await _auth.verifySignUpOtp(
          email: (data['email'] as String).trim().toLowerCase(),
          token: token,
        );
      }

      // A session is what makes this a sign-in. Verification also answers
      // with a user and no session for the first step of a secure email /
      // phone change — accepting that would flip the app to "signed in"
      // with no credentials behind it.
      final user = outcome.user;
      if (!outcome.hasSession || user == null) {
        throw AuthException((l) => l.authErrorVerificationFailed);
      }
      _pendingPhoneMetadata = null;
      await _ensureSignedIn(user);
      if (_accountDisabled) {
        throw AuthException((l) => l.authErrorAccountDisabled);
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
    } on AuthBackendException catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      developer.log(
        'verifyOtp failure: ${e.failure.name} (${e.code} – ${e.message})',
        name: 'AuthProvider',
      );
      switch (e.failure) {
        case AuthFailure.network:
          throw AuthException((l) => l.errorNetwork);
        // A wrong code and an expired one are the same answer here, and
        // the backend may not distinguish them — GoTrue reports a bad code
        // as `invalid_credentials`, the same code it uses for a wrong
        // password.
        case AuthFailure.otpExpired:
        case AuthFailure.invalidCredentials:
          throw AuthException((l) => l.authErrorInvalidCode);
        case AuthFailure.rateLimited:
          throw AuthException((l) => l.authErrorTooManyAttemptsRetry);
        default:
          throw AuthException((l) => l.authErrorVerificationFailed);
      }
    } on Exception catch (e) {
      _isLoading = false;
      _justLoggedIn = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.verifyOtpAndLogin');
      throw AuthException((l) => l.authErrorVerifyCodeFailed);
    }
  }

  Future<void> resendVerificationLink() async {
    final email = pendingEmail;
    if (email == null || email.isEmpty) {
      throw AuthException((l) => l.authErrorNotLoggedIn);
    }
    try {
      await sendOtpForEmail(email);
    } on AuthException {
      rethrow;
    } on Exception catch (_) {
      throw AuthException((l) => l.authErrorResendFailed);
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
      await _auth.sendPasswordResetCode(email.trim().toLowerCase());
      _isLoading = false;
      notifyListeners();
    } on AuthBackendException catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.sendPasswordResetEmail');
      if (e.failure == AuthFailure.network) {
        throw AuthException((l) => l.authErrorNetworkRetry);
      }
      // Recovery mail is throttled per address and per project; say so
      // instead of "failed to send", which invites an immediate retry.
      if (e.failure == AuthFailure.rateLimited) {
        throw AuthException((l) => l.authErrorTooManyAttempts);
      }
      throw AuthException((l) => l.authErrorResetEmailFailed);
    } on Exception catch (e) {
      _isLoading = false;
      notifyListeners();
      ErrorHandler.logError(e, context: 'AuthProvider.sendPasswordResetEmail');
      throw AuthException((l) => l.authErrorResetEmailFailed);
    }
  }

  /// Completes a password reset with the recovery [code] emailed to
  /// [email].
  ///
  /// Once the code has been accepted the temporary recovery session is
  /// always signed out — whether the password change then succeeded or not
  /// — so the user comes back through the login screen and no recovery
  /// session is left behind. A code that is *refused* leaves any session
  /// that already existed alone: this screen is reachable while signed in,
  /// and a typo must not log the user out.
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    var codeAccepted = false;
    try {
      _isLoading = true;
      _recovering = true;
      notifyListeners();
      await _auth.verifyRecoveryOtp(
        email: email.trim().toLowerCase(),
        token: code.trim(),
      );
      codeAccepted = true;
      await _auth.updatePassword(newPassword);
    } on AuthBackendException catch (e) {
      ErrorHandler.logError(e, context: 'AuthProvider.confirmPasswordReset');
      switch (e.failure) {
        case AuthFailure.weakPassword:
          throw AuthException((l) => l.authErrorResetWeakPassword);
        // As in [verifyOtpAndLogin]: a refused code may arrive as either.
        case AuthFailure.otpExpired:
        case AuthFailure.invalidCredentials:
          throw AuthException((l) => l.authErrorResetCodeInvalid);
        case AuthFailure.samePassword:
          throw AuthException((l) => l.authErrorResetSamePassword);
        default:
          throw AuthException((l) => l.authErrorResetFailed);
      }
    } on Exception catch (e) {
      ErrorHandler.logError(e, context: 'AuthProvider.confirmPasswordReset');
      throw AuthException((l) => l.authErrorResetFailed);
    } finally {
      try {
        if (codeAccepted && _auth.currentUser != null) await _auth.signOut();
      } on Exception catch (_) {}
      _recovering = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Abandons a recovery session without changing the password (the user
  /// closed the reset screen). The session is dropped so the app does not
  /// stay signed in on the strength of an email link alone.
  Future<void> cancelPasswordRecovery() async {
    _passwordRecoveryPending = false;
    notifyListeners();
    try {
      if (_auth.currentUser != null) await _auth.signOut();
    } on Exception catch (e) {
      ErrorHandler.logError(e, context: 'AuthProvider.cancelPasswordRecovery');
    }
  }

  /// Sets a new password for a recovery session that arrived via the link in
  /// the recovery email (rather than via a typed code).
  ///
  /// The session is already the user's, so there is no code to verify — only
  /// the password to change. As with [confirmPasswordReset] the session is
  /// dropped afterwards, so the next sign-in uses the new password.
  Future<void> completePasswordRecovery(String newPassword) async {
    try {
      _isLoading = true;
      _recovering = true;
      notifyListeners();
      await _auth.updatePassword(newPassword);
    } on AuthBackendException catch (e) {
      ErrorHandler.logError(
        e,
        context: 'AuthProvider.completePasswordRecovery',
      );
      switch (e.failure) {
        case AuthFailure.weakPassword:
          throw AuthException((l) => l.authErrorResetWeakPassword);
        case AuthFailure.samePassword:
          throw AuthException((l) => l.authErrorResetSamePassword);
        case AuthFailure.sessionExpired:
          throw AuthException((l) => l.authErrorResetCodeInvalid);
        default:
          throw AuthException((l) => l.authErrorResetFailed);
      }
    } on Exception catch (e) {
      ErrorHandler.logError(
        e,
        context: 'AuthProvider.completePasswordRecovery',
      );
      throw AuthException((l) => l.authErrorResetFailed);
    } finally {
      _recovering = false;
      _isLoading = false;
      // Cleared whether or not the change succeeded: leaving it raised would
      // trap the user on the reset screen with a session they cannot use.
      _passwordRecoveryPending = false;
      try {
        if (_auth.currentUser != null) await _auth.signOut();
      } on Exception catch (_) {}
      notifyListeners();
    }
  }

  // ─────────────────────────── Biometrics ──────────────────────────────────

  /// Unlocks with biometrics using the persisted session. Returns
  /// false when there is no usable session (the user must sign in with
  /// their password).
  Future<bool> authenticateWithBiometrics({String? promptReason}) async {
    try {
      final isBiometricEnabled = await _storage.isBiometricEnabled(
        forUserId: _db.currentUserId,
      );
      if (!isBiometricEnabled) return false;

      final authenticated = await _biometricService.authenticateForLogin(
        reason: promptReason ?? englishL10n.biometricLoginPrompt,
      );
      if (!authenticated) return false;

      final isValid = await _isServerSessionValid();
      if (!isValid) return false;

      final user = _auth.currentUser;
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

  /// [promptReason] is the localised text of the system biometric prompt.
  Future<void> setBiometricEnabled(bool enabled, {String? promptReason}) async {
    if (enabled) {
      final canAuth = await _biometricService.authenticate(
        reason: promptReason ?? englishL10n.biometricEnablePrompt,
      );
      if (!canAuth) throw AuthException((l) => l.biometricErrorFailed);
    }
    final user = _auth.currentUser;
    await _storage.setBiometricEnabled(enabled, userId: user?.id);
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

  /// Whether the signed-in account enabled the biometric lock on this
  /// device.
  Future<bool> isBiometricEnabled() => _storage.isBiometricEnabled(
    forUserId: _currentUser?.id ?? _auth.currentUser?.id,
  );
  Future<bool> isBiometricAvailable() =>
      _biometricService.isBiometricAvailable();

  /// Whether the biometric-login setting can be offered at all (hardware
  /// present *and* a fingerprint/face enrolled). Settings and Profile both
  /// gate their control on this.
  Future<bool> isBiometricUsable() => _biometricService.isBiometricUsable();

  // ─────────────────────────── Session ─────────────────────────────────────

  /// Pushes the inactivity timeout forward (called on pointer events and
  /// route changes from the app root).
  void recordActivity() {
    if (_isAuthenticated && !_isLocked) _sessionManager.recordActivity();
  }

  Future<bool> validateSession() => _isServerSessionValid();

  Future<bool> _isServerSessionValid() async {
    if (!_auth.isConfigured) return false;
    if (!_auth.hasSession) {
      developer.log('No persisted session.', name: 'AuthProvider');
      return false;
    }
    try {
      if (_auth.isSessionExpired) {
        await _auth.refreshSession();
      }
      await _sessionManager.extendSession();
      return true;
    } on AuthBackendException catch (e) {
      if (e.failure == AuthFailure.network) {
        // Offline — allow access with the cached session.
        developer.log('Session refresh offline: $e', name: 'AuthProvider');
        return true;
      }
      developer.log('Session invalid: ${e.failure.name}', name: 'AuthProvider');
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

  /// Why the user was signed out without asking (account disabled or
  /// deleted); shown once by the UI, see [takeSignOutNotice].
  LocalizedText? _signOutNotice;

  /// Returns and clears the pending forced sign-out message, if any.
  LocalizedText? takeSignOutNotice() {
    final notice = _signOutNotice;
    _signOutNotice = null;
    return notice;
  }

  /// Signs out. [notice] is the message to show the user when the sign-out
  /// was not requested by them.
  Future<void> logout({LocalizedText? notice}) async {
    // Cancel any sign-in still in flight right away.
    _authGen++;
    if (notice != null) _signOutNotice = notice;
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
      await _auth.signOut();

      // The biometric lock is per account: it must not carry over to the
      // next account signing in on this device.
      await _storage.clearAll();

      _resetUserState();
      _isLoading = false;
      notifyListeners();
      // The signedOut auth event notifies too; listeners are idempotent.
      _notifyAll(_signOutListeners, 'Sign-out');
    } on Exception catch (e) {
      _resetUserState();
      _isLoading = false;
      notifyListeners();
      _notifyAll(_signOutListeners, 'Sign-out');
      ErrorHandler.logError(e, context: 'AuthProvider.logout');
    }
  }

  // ─────────────────────────── Helpers ─────────────────────────────────────

  Future<void> _startUserSession(
    AuthUser user,
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
    _initTimer?.cancel();
    _authSub.cancel();
    _profileSub?.cancel();
    _sessionManager.dispose();
    super.dispose();
  }
}
