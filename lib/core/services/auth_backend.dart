/// The app's own auth vocabulary: a user, a state change, a refusal.
///
/// Phase 5 removed the data layer's dependency on `supabase_flutter` by
/// naming what a refusal *means* instead of which SQLSTATE carried it. The
/// auth layer had the same coupling in a different shape: `auth_provider.dart`
/// held 116 references to `sb.User`, `sb.AuthException`, `sb.OtpType` and
/// `sb.UserAttributes`, and nine `switch (e.code)` blocks branching on
/// GoTrue's string codes — `otp_expired`, `over_email_send_rate_limit`,
/// `email_not_confirmed`, and so on.
///
/// Those codes are GoTrue's. Appwrite has none of them: it answers with HTTP
/// statuses and its own `type` strings. So the same move applies — name the
/// conditions here, in terms of what happened, and let the adapter translate.
///
/// Unlike [BackendFailure] this is an *interface*, not a registry of
/// functions: the call sites all hold a service reference already, so an
/// injected adapter is the honest seam. `backend_failure.dart` is a registry
/// only because its call sites are pure functions with nowhere to put one.
library;

import 'package:climate_app/core/utils/error_handler.dart' show SecureException;

/// A signed-in (or just-authenticated) account, in the fields this app
/// actually reads.
///
/// Deliberately not a passthrough of the vendor's user object: everything
/// here has a counterpart in both backends, and anything that does not —
/// GoTrue's `identities`, `appMetadata`, `role` — stays inside the adapter.
class AuthUser {
  const AuthUser({
    required this.id,
    this.email,
    this.phone,
    this.emailConfirmed = false,
    this.phoneConfirmed = false,
    this.createdAt,
    this.metadata = const {},
  });

  final String id;
  final String? email;
  final String? phone;

  /// Whether the address has been confirmed.
  ///
  /// A bool rather than the timestamp GoTrue stores, because the app only
  /// ever asks the yes/no question and Appwrite only answers it — carrying
  /// a timestamp here would mean the Appwrite adapter inventing one.
  final bool emailConfirmed;
  final bool phoneConfirmed;

  /// When the account was created — shown on the profile screen as the
  /// registration date.
  final DateTime? createdAt;

  /// The account's own metadata (GoTrue's `user_metadata`; in Appwrite the
  /// `prefs` object). The app reads `name` from it in one place, as the
  /// fallback before the profile document has loaded.
  final Map<String, dynamic> metadata;

  /// True once either address has been confirmed. The provider uses this to
  /// avoid sending an already-confirmed user to the verify screen when the
  /// profile row cannot be fetched.
  bool get isConfirmed => emailConfirmed || phoneConfirmed;

  /// The display name from metadata, or null when it is absent or blank.
  String? get metadataName {
    final value = metadata['name'];
    return (value is String && value.trim().isNotEmpty) ? value : null;
  }
}

/// Why an auth call failed, in conditions rather than vendor codes.
///
/// One value per *server condition*, not per call site: `providerDisabled`
/// means the same thing during sign-up and during a phone OTP, even though
/// the sentence shown to the user differs. Choosing that sentence is the
/// provider's job and stays in the flow that knows the context.
enum AuthFailure {
  /// The request never reached the server. The only failure this app treats
  /// as "carry on offline" rather than as an answer.
  network,

  /// Wrong password, or no such account. GoTrue conflates these two
  /// deliberately, to avoid confirming which addresses exist, and so do we.
  ///
  /// It also uses the same code for a bad OTP, so the OTP flows treat this
  /// and [otpExpired] alike. That is not an accident of this mapping — it is
  /// GoTrue's behaviour today and the call sites already allow for it.
  invalidCredentials,

  /// The address exists but has never been confirmed.
  emailNotConfirmed,

  /// Registration refused because the address or number is already taken.
  accountExists,

  /// The account has been banned server-side.
  accountBanned,

  /// The address did not pass the server's validation.
  invalidEmail,

  /// The sign-up method itself is turned off — registration disabled, or the
  /// email / phone provider not configured.
  providerDisabled,

  /// The provider accepted the request and failed to deliver the message.
  deliveryFailed,

  /// One-time codes are not enabled for this account, which is how GoTrue
  /// answers a phone sign-in for a number it does not know.
  otpDisabled,

  /// Too many requests. Covers the per-address mail throttle, the SMS
  /// throttle and the project-wide request limit — the app says the same
  /// thing for all three.
  rateLimited,

  /// The code was valid once and no longer is.
  otpExpired,

  /// The new password did not meet the server's policy.
  weakPassword,

  /// The new password is the current one.
  samePassword,

  /// The session backing this call is gone or unusable.
  sessionExpired,

  /// The server wants a fresh sign-in before it will make this change.
  reauthenticationNeeded,

  /// Not a condition this app knows how to describe. Callers must fall back
  /// to a generic message rather than guessing.
  unknown,
}

/// An auth call the backend refused.
///
/// [code] and [message] are the server's own, kept for the log line only —
/// no control flow may branch on them, or the coupling comes straight back.
class AuthBackendException implements Exception {
  const AuthBackendException(this.failure, {this.code, this.message});

  final AuthFailure failure;
  final String? code;
  final String? message;

  @override
  String toString() => 'AuthBackendException(${failure.name}, $code: $message)';
}

/// What happened to the session, as the provider needs to know it.
enum AuthEvent {
  /// The session restored at startup.
  initialSession,
  signedIn,
  signedOut,

  /// The access token was renewed; the account is unchanged.
  tokenRefreshed,

  /// The account record changed (email, metadata).
  userUpdated,

  /// A recovery link was opened: the session is valid, but the user must
  /// choose a new password before anything else.
  passwordRecovery,

  /// Anything the app does not act on (MFA, re-auth challenges).
  other,
}

/// An [AuthEvent] and the account it concerns.
///
/// [user] is null exactly when there is no session — which is the only
/// property of the session object the provider ever reads.
class AuthChange {
  const AuthChange(this.event, this.user);

  final AuthEvent event;
  final AuthUser? user;

  bool get hasSession => user != null;
}

/// The result of a call that may or may not have established a session.
///
/// Sign-up with confirmations on returns a user and no session; `verifyOTP`
/// can do the same for the first step of a secure email change. Both of
/// those are load-bearing distinctions in this app, so the two facts stay
/// separate rather than collapsing into a nullable user.
class AuthOutcome {
  const AuthOutcome({this.user, this.hasSession = false});

  final AuthUser? user;
  final bool hasSession;
}

/// Everything `AuthProvider` and `ProfileProvider` need from an auth server.
///
/// Phase 2 of the migration maps each of these onto Appwrite; the two that
/// need a server API key there (minting a typed code, completing a recovery)
/// become Function calls behind the same two methods.
abstract interface class AuthBackend {
  /// False when no backend is configured — the app then behaves as signed
  /// out rather than throwing on every call.
  bool get isConfigured;

  /// Sign-ins, sign-outs, refreshes and recovery sessions.
  Stream<AuthChange> get changes;

  /// The signed-in account, or null.
  AuthUser? get currentUser;

  /// Whether a session is persisted on this device. The biometric unlock
  /// re-uses it; after a logout there is none.
  bool get hasSession;

  /// Whether that session's access token has expired. False when there is
  /// no session at all.
  bool get isSessionExpired;

  Future<AuthOutcome> signUpWithPassword({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  });

  Future<AuthOutcome> signInWithPassword({
    required String email,
    required String password,
  });

  /// Sends an SMS code. With [createUser] false an unknown number is
  /// refused rather than registered.
  Future<void> sendPhoneOtp({
    required String phone,
    required bool createUser,
    Map<String, dynamic>? data,
  });

  /// Re-sends the sign-up confirmation code.
  Future<void> resendSignUpCode(String email);

  Future<AuthOutcome> verifySignUpOtp({
    required String email,
    required String token,
  });

  Future<AuthOutcome> verifyPhoneOtp({
    required String phone,
    required String token,
  });

  /// Redeems a recovery code. Establishes a session that is only good for
  /// the password change that follows it.
  Future<void> verifyRecoveryOtp({
    required String email,
    required String token,
  });

  /// Sends the recovery code. Must not reveal whether the address exists.
  Future<void> sendPasswordResetCode(String email);

  /// Changes the password of the current session.
  ///
  /// Both call sites are password *recovery*: the session was established
  /// by a code the user typed, so there is no old password to supply. An
  /// adapter whose API demands one does this through its server-side
  /// Function instead.
  Future<void> updatePassword(String newPassword);

  /// Starts an email change. Both backends confirm it out of band.
  ///
  /// [password] is the account's current one. Supabase does not ask for it;
  /// Appwrite does, and an adapter that needs it and is not given it must
  /// raise [AuthFailure.reauthenticationNeeded] rather than guess — which
  /// is a condition `ProfileProvider` already has wording for.
  Future<void> updateEmail(String newEmail, {String? password});

  /// Re-fetches the account record from the server, so a confirmation or
  /// metadata change made elsewhere is picked up. Null when signed out.
  Future<AuthUser?> reloadUser();

  /// Renews the access token in place.
  Future<void> refreshSession();

  /// Ends the session, server-side where the backend supports it. Must not
  /// throw: a sign-out that fails still has to clear local state.
  Future<void> signOut();
}

/// Thrown when an auth call is made with no backend configured.
class AuthBackendNotConfigured extends SecureException {
  AuthBackendNotConfigured() : super((l) => l.errorContactSupport);
}
