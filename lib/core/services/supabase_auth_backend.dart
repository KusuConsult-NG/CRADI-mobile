import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:climate_app/core/router/route_guard.dart'
    show kPasswordResetRedirect;
import 'package:climate_app/core/services/auth_backend.dart';
import 'package:climate_app/core/services/supabase_service.dart';

/// [AuthBackend] over Supabase Auth (GoTrue).
///
/// Everything GoTrue-shaped lives here: the string error codes, `OtpType`,
/// `UserAttributes`, the recovery `redirectTo`, and the one behaviour that
/// is not an error at all but means the same thing as one (below).
class SupabaseAuthBackend implements AuthBackend {
  SupabaseAuthBackend([SupabaseService? service])
    : _db = service ?? SupabaseService();

  final SupabaseService _db;

  @override
  bool get isConfigured => SupabaseService.isReady;

  @override
  Stream<AuthChange> get changes => _db.authStateChanges.map(_toChange);

  @override
  AuthUser? get currentUser => toAuthUser(_db.getCurrentUser());

  @override
  bool get hasSession =>
      SupabaseService.isReady && _db.auth.currentSession != null;

  @override
  bool get isSessionExpired => _db.auth.currentSession?.isExpired ?? false;

  // ─────────────────────────── Mapping ──────────────────────────────────

  /// Visible for the two files that still receive a `sb.User` from
  /// elsewhere in the SDK and need it in the app's own shape.
  static AuthUser? toAuthUser(sb.User? user) {
    if (user == null) return null;
    return AuthUser(
      id: user.id,
      email: user.email,
      phone: user.phone,
      emailConfirmed: user.emailConfirmedAt != null,
      phoneConfirmed: user.phoneConfirmedAt != null,
      createdAt: _parseTimestamp(user.createdAt),
      metadata: user.userMetadata ?? const {},
    );
  }

  /// GoTrue returns these as ISO-8601 strings, not `DateTime`.
  static DateTime? _parseTimestamp(String? value) =>
      value == null ? null : DateTime.tryParse(value);

  static AuthChange _toChange(sb.AuthState state) =>
      AuthChange(switch (state.event) {
        sb.AuthChangeEvent.initialSession => AuthEvent.initialSession,
        sb.AuthChangeEvent.signedIn => AuthEvent.signedIn,
        sb.AuthChangeEvent.signedOut => AuthEvent.signedOut,
        sb.AuthChangeEvent.tokenRefreshed => AuthEvent.tokenRefreshed,
        sb.AuthChangeEvent.userUpdated => AuthEvent.userUpdated,
        sb.AuthChangeEvent.passwordRecovery => AuthEvent.passwordRecovery,
        _ => AuthEvent.other,
      }, toAuthUser(state.session?.user));

  static AuthOutcome _toOutcome(sb.AuthResponse response) => AuthOutcome(
    user: toAuthUser(response.session?.user ?? response.user),
    hasSession: response.session != null,
  );

  /// Translates GoTrue's failures into the app's conditions.
  ///
  /// Visible for tests: every branch below is a code this app has handled
  /// in production, and the mapping is the whole correctness of this file.
  ///
  /// `AuthRetryableFetchException` is a transport failure, which is the one
  /// case the app must not treat as the server's answer: it keeps a cached
  /// session alive rather than signing the user out.
  @visibleForTesting
  static AuthBackendException translate(sb.AuthException e) {
    final failure = switch (e) {
      sb.AuthRetryableFetchException() => AuthFailure.network,
      sb.AuthWeakPasswordException() => AuthFailure.weakPassword,
      _ => switch (e.code) {
        'weak_password' => AuthFailure.weakPassword,
        'invalid_credentials' ||
        'user_not_found' => AuthFailure.invalidCredentials,
        'email_not_confirmed' => AuthFailure.emailNotConfirmed,
        'user_already_exists' ||
        'email_exists' ||
        'phone_exists' => AuthFailure.accountExists,
        'user_banned' => AuthFailure.accountBanned,
        'email_address_invalid' ||
        'validation_failed' => AuthFailure.invalidEmail,
        'signup_disabled' ||
        'email_provider_disabled' ||
        'phone_provider_disabled' => AuthFailure.providerDisabled,
        'sms_send_failed' => AuthFailure.deliveryFailed,
        'otp_disabled' => AuthFailure.otpDisabled,
        'over_email_send_rate_limit' ||
        'over_sms_send_rate_limit' ||
        'over_request_rate_limit' => AuthFailure.rateLimited,
        'otp_expired' => AuthFailure.otpExpired,
        'same_password' => AuthFailure.samePassword,
        'session_not_found' || 'bad_jwt' => AuthFailure.sessionExpired,
        'reauthentication_needed' => AuthFailure.reauthenticationNeeded,
        _ => AuthFailure.unknown,
      },
    };
    return AuthBackendException(failure, code: e.code, message: e.message);
  }

  /// Runs [body], translating GoTrue's exceptions on the way out.
  static Future<T> _mapped<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on sb.AuthException catch (e) {
      throw translate(e);
    }
  }

  // ─────────────────────────── Calls ────────────────────────────────────

  @override
  Future<AuthOutcome> signUpWithPassword({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) => _mapped(() async {
    final response = await _db.auth.signUp(
      email: email,
      password: password,
      data: data,
    );

    // Not an error from GoTrue, but it means exactly what one does. With
    // email confirmations on, signing up with an address that is already
    // registered returns 200 and an obfuscated user with no identities,
    // rather than refusing — deliberately, so the response cannot be used
    // to enumerate accounts. The caller needs the same answer either way,
    // and recognising the shape is this adapter's job, not the provider's.
    final identities = response.user?.identities;
    if (response.session == null && identities != null && identities.isEmpty) {
      throw const AuthBackendException(
        AuthFailure.accountExists,
        code: 'obfuscated_signup',
        message: 'Sign-up returned a user with no identities',
      );
    }

    return _toOutcome(response);
  });

  @override
  Future<AuthOutcome> signInWithPassword({
    required String email,
    required String password,
  }) => _mapped(
    () async => _toOutcome(
      await _db.auth.signInWithPassword(email: email, password: password),
    ),
  );

  @override
  Future<void> sendPhoneOtp({
    required String phone,
    required bool createUser,
    Map<String, dynamic>? data,
  }) => _mapped(
    () => _db.auth.signInWithOtp(
      phone: phone,
      shouldCreateUser: createUser,
      data: data,
    ),
  );

  @override
  Future<void> resendSignUpCode(String email) =>
      _mapped(() => _db.auth.resend(type: sb.OtpType.signup, email: email));

  @override
  Future<AuthOutcome> verifySignUpOtp({
    required String email,
    required String token,
  }) => _mapped(
    () async => _toOutcome(
      await _db.auth.verifyOTP(
        type: sb.OtpType.signup,
        email: email,
        token: token,
      ),
    ),
  );

  @override
  Future<AuthOutcome> verifyPhoneOtp({
    required String phone,
    required String token,
  }) => _mapped(
    () async => _toOutcome(
      await _db.auth.verifyOTP(
        type: sb.OtpType.sms,
        phone: phone,
        token: token,
      ),
    ),
  );

  @override
  Future<void> verifyRecoveryOtp({
    required String email,
    required String token,
  }) => _mapped(
    () => _db.auth.verifyOTP(
      type: sb.OtpType.recovery,
      email: email,
      token: token,
    ),
  );

  @override
  Future<void> sendPasswordResetCode(String email) => _mapped(
    () => _db.auth.resetPasswordForEmail(
      email,
      // Without this the link in the mail is built from the project's Site
      // URL, which is the admin panel — app users who tapped it landed on a
      // staff login screen. On web there is no app to open, so the Site URL
      // (the browser reset page) remains the right destination.
      redirectTo: kIsWeb ? null : kPasswordResetRedirect,
    ),
  );

  @override
  Future<void> updatePassword(String newPassword) => _mapped(
    () => _db.auth.updateUser(sb.UserAttributes(password: newPassword)),
  );

  @override
  Future<void> updateEmail(String newEmail, {String? password}) =>
      // GoTrue re-confirms by mail and does not ask for the password.
      _mapped(() => _db.auth.updateUser(sb.UserAttributes(email: newEmail)));

  @override
  Future<AuthUser?> reloadUser() =>
      _mapped(() async => toAuthUser(await _db.reloadCurrentUser()));

  @override
  Future<void> refreshSession() => _mapped(() => _db.auth.refreshSession());

  @override
  Future<void> signOut() => _db.logout();
}
