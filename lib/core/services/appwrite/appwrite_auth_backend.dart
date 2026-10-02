import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:appwrite/appwrite.dart' as aw;
import 'package:appwrite/enums.dart' show ExecutionMethod;
import 'package:appwrite/models.dart' as awm;

import 'package:climate_app/core/services/appwrite/appwrite_config.dart';
import 'package:climate_app/core/services/appwrite/appwrite_data_backend.dart';
import 'package:climate_app/core/services/appwrite/appwrite_errors.dart';
import 'package:climate_app/core/services/auth_backend.dart';

/// [AuthBackend] over Appwrite.
///
/// The shape comes from Phase 2, which proved the one endpoint the whole
/// design rests on: `POST /users/{id}/tokens` mints a secret of **any
/// length we choose**, so the app's six-digit code-entry screens survive
/// intact instead of becoming email links. That call needs a server API
/// key, so it lives in a Function — and so, therefore, does every step
/// that touches it.
///
/// ## Which side does what
///
/// | | where | why |
/// |---|---|---|
/// | sign in, sign out, sessions | client | ordinary session endpoints |
/// | register, resend a code, ask for recovery | **Function** | mints a token with a server key |
/// | redeem a typed code | **Function** | see below |
/// | set a password after recovery | **Function** | no old password to supply |
/// | change email | client | Appwrite asks for the password |
///
/// Redeeming a code is the subtle one. `account.createSession` needs a
/// `userId`, and the client has only the address the user typed. Handing
/// the client a `userId` in exchange for an address would be an account
/// enumeration oracle, which Phase 2 lists as a risk to preserve against —
/// Appwrite's own recovery endpoint deliberately does not reveal whether
/// an address exists. So the Function does the exchange: it takes the
/// address *and* the code together, resolves the user itself, redeems the
/// token, and returns a session secret. An unknown address and a wrong
/// code are answered identically.
///
/// **Status: not exercised against a server.** The error table is tested.
/// Everything that needs a socket is written against the SDK and Phase 2's
/// verified sequences, and is unverified until there is a project to point
/// it at.
class AppwriteAuthBackend implements AuthBackend {
  AppwriteAuthBackend({AppwriteDataBackend? data, aw.Client? client})
    : _data = data,
      _client = client ?? data?.client ?? _defaultClient() {
    _account = aw.Account(_client);
    _functions = aw.Functions(_client);
  }

  static aw.Client _defaultClient() => aw.Client()
      .setEndpoint(AppwriteConfig.endpoint)
      .setProject(AppwriteConfig.projectId);

  final aw.Client _client;
  final AppwriteDataBackend? _data;
  late final aw.Account _account;
  late final aw.Functions _functions;

  final StreamController<AuthChange> _changes =
      StreamController<AuthChange>.broadcast();

  /// Appwrite exposes the account over the network only, while
  /// `AuthBackend.currentUser` is synchronous — the router reads it on
  /// every redirect. So it is cached, and [restore] seeds it at startup.
  AuthUser? _cached;
  String? _sessionId;

  @override
  bool get isConfigured => AppwriteConfig.isConfigured;

  @override
  Stream<AuthChange> get changes => _changes.stream;

  @override
  AuthUser? get currentUser => _cached;

  @override
  bool get hasSession => _cached != null;

  /// Appwrite sessions last a year and the SDK renews the cookie itself,
  /// so there is no client-visible expiry to test. [refreshSession] still
  /// exists, and `AuthProvider` calls it when this answers true — it never
  /// does, which is correct rather than a stub: an expired Appwrite
  /// session fails the next call with `user_session_not_found`, and that
  /// is already mapped to [AuthFailure.sessionExpired].
  @override
  bool get isSessionExpired => false;

  // ───────────────────────── session state ────────────────────────────

  /// Reads the persisted session at startup and announces it, which is
  /// what `AuthProvider` waits for before leaving the splash screen.
  Future<void> restore() async {
    if (!isConfigured) {
      _emit(AuthEvent.initialSession, null);
      return;
    }
    try {
      final user = await _account.get();
      _adopt(user);
      _emit(AuthEvent.initialSession, _cached);
    } on aw.AppwriteException catch (e) {
      developer.log(
        'No restorable session: ${e.type ?? e.code}',
        name: 'AppwriteAuthBackend',
      );
      _forget();
      _emit(AuthEvent.initialSession, null);
    }
  }

  void _adopt(awm.User user) {
    _cached = toAuthUser(user);
    _data?.setCurrentUserId(user.$id);
  }

  void _forget() {
    _cached = null;
    _sessionId = null;
    _data?.setCurrentUserId(null);
  }

  void _emit(AuthEvent event, AuthUser? user) {
    if (!_changes.isClosed) _changes.add(AuthChange(event, user));
  }

  /// Appwrite's account record in the app's shape.
  static AuthUser toAuthUser(awm.User user) => AuthUser(
    id: user.$id,
    email: user.email.isEmpty ? null : user.email,
    phone: user.phone.isEmpty ? null : user.phone,
    emailConfirmed: user.emailVerification,
    phoneConfirmed: user.phoneVerification,
    createdAt: DateTime.tryParse(user.$createdAt),
    // Appwrite's `prefs` is the counterpart of GoTrue's user_metadata; the
    // app reads `name` from it before the profile document has loaded.
    metadata: Map<String, dynamic>.from(user.prefs.data),
  );

  /// Adopts a session the server just handed us and announces the sign-in.
  Future<AuthOutcome> _establish(
    String sessionSecret, {
    String? sessionId,
  }) async {
    _client.setSession(sessionSecret);
    final user = await _account.get();
    _adopt(user);
    _sessionId = sessionId;
    _emit(AuthEvent.signedIn, _cached);
    return AuthOutcome(user: _cached, hasSession: true);
  }

  // ───────────────────────── calls ────────────────────────────────────

  @override
  Future<AuthOutcome> signUpWithPassword({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    // Registration is a Function because the profile document is
    // Function-written (Phase 1: role, approval and ward are the inputs to
    // every other rule, so the client may never set them) and because the
    // confirmation code is server-minted.
    await _call('signUp', {
      'email': email,
      'password': password,
      'metadata': data ?? const <String, dynamic>{},
    });
    // No session: the user types the emailed code next, exactly as on
    // Supabase with confirmations on.
    return const AuthOutcome();
  }

  @override
  Future<AuthOutcome> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final session = await _account.createEmailPasswordSession(
        email: email,
        password: password,
      );
      final user = await _account.get();
      _adopt(user);
      _sessionId = session.$id;
      _emit(AuthEvent.signedIn, _cached);

      // Appwrite signs an unverified account in; GoTrue refuses it. The
      // app's login screen depends on the refusal — it is what sends the
      // user to the code-entry screen with a fresh code. So the check
      // moves here, and the session is dropped again before raising it.
      if (!user.emailVerification && !user.phoneVerification) {
        await signOut();
        throw const AuthBackendException(
          AuthFailure.emailNotConfirmed,
          code: 'user_unverified',
        );
      }
      return AuthOutcome(user: _cached, hasSession: true);
    } on aw.AppwriteException catch (e) {
      throw toAuthBackendException(e);
    }
  }

  @override
  Future<void> sendPhoneOtp({
    required String phone,
    required bool createUser,
    Map<String, dynamic>? data,
  }) async {
    // `AuthProvider.phoneAuthEnabled` is false and Phase 2 does not
    // migrate phone sign-in. Saying so is better than a half-built path
    // that looks available.
    throw const AuthBackendException(
      AuthFailure.providerDisabled,
      code: 'phone_auth_not_migrated',
      message: 'Phone sign-in is not available on this backend',
    );
  }

  @override
  Future<void> resendSignUpCode(String email) =>
      _call('resendSignUpCode', {'email': email}).then((_) {});

  @override
  Future<AuthOutcome> verifySignUpOtp({
    required String email,
    required String token,
  }) async {
    final body = await _call('verifySignUp', {'email': email, 'code': token});
    return _establish(_secretOf(body));
  }

  @override
  Future<AuthOutcome> verifyPhoneOtp({
    required String phone,
    required String token,
  }) => sendPhoneOtp(
    phone: phone,
    createUser: false,
  ).then((_) => const AuthOutcome());

  @override
  Future<void> verifyRecoveryOtp({
    required String email,
    required String token,
  }) async {
    final body = await _call('verifyRecovery', {'email': email, 'code': token});
    // The recovery session is only good for the password change that
    // follows, which is why `confirmPasswordReset` signs out afterwards
    // whether or not the change succeeded.
    await _establish(_secretOf(body));
  }

  @override
  Future<void> sendPasswordResetCode(String email) =>
      // Must answer identically for an address that does not exist. The
      // Function mints nothing for an unknown one and returns the same
      // body, so there is nothing to vary here.
      _call('sendRecoveryCode', {'email': email}).then((_) {});

  @override
  Future<void> updatePassword(String newPassword) async {
    // Both call sites are recovery: the session came from a typed code, so
    // there is no old password, and `account.updatePassword` demands one
    // for an account that has a password set. The Function holds the
    // server key and sets it for the session's own user.
    await _call('setPassword', {'password': newPassword});
  }

  @override
  Future<void> updateEmail(String newEmail, {String? password}) async {
    if (password == null || password.isEmpty) {
      // Appwrite will not change an address without the current password.
      // Raising the condition the app already has wording for beats
      // failing with a bare 401 — `ProfileProvider` shows "please sign in
      // again to change your email".
      throw const AuthBackendException(
        AuthFailure.reauthenticationNeeded,
        code: 'password_required',
        message: 'Appwrite requires the current password to change the email',
      );
    }
    try {
      final user = await _account.updateEmail(
        email: newEmail,
        password: password,
      );
      _adopt(user);
      _emit(AuthEvent.userUpdated, _cached);
    } on aw.AppwriteException catch (e) {
      throw toAuthBackendException(e);
    }
  }

  @override
  Future<AuthUser?> reloadUser() async {
    if (!isConfigured) return null;
    try {
      final user = await _account.get();
      _adopt(user);
      _emit(AuthEvent.userUpdated, _cached);
      return _cached;
    } on aw.AppwriteException catch (e) {
      throw toAuthBackendException(e);
    }
  }

  @override
  Future<void> refreshSession() async {
    try {
      await _account.updateSession(sessionId: _sessionId ?? 'current');
      _emit(AuthEvent.tokenRefreshed, _cached);
    } on aw.AppwriteException catch (e) {
      throw toAuthBackendException(e);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _account.deleteSession(sessionId: _sessionId ?? 'current');
    } on aw.AppwriteException catch (e) {
      // `signOut` must not throw: a sign-out that fails server-side still
      // has to clear local state, or the app is stuck signed in to a
      // session it cannot use.
      developer.log(
        'signOut: ${e.type ?? e.code}',
        name: 'AppwriteAuthBackend',
      );
    }
    _client.setSession('');
    _forget();
    _emit(AuthEvent.signedOut, null);
  }

  void dispose() => unawaited(_changes.close());

  // ───────────────────────── the Function ─────────────────────────────

  static String _secretOf(Map<String, dynamic> body) {
    final secret = body['sessionSecret'];
    if (secret is String && secret.isNotEmpty) return secret;
    throw const AuthBackendException(
      AuthFailure.unknown,
      code: 'function_contract',
      message: 'The auth Function returned no session',
    );
  }

  /// One call into the auth Function, with its refusals translated.
  ///
  /// A Function that refuses answers with a 4xx *inside* a successful
  /// execution, so the status has to be read off the response rather than
  /// caught. Its `type` is the same slug vocabulary the API uses, which is
  /// what lets one error table serve both.
  Future<Map<String, dynamic>> _call(
    String action,
    Map<String, dynamic> payload,
  ) async {
    final awm.Execution execution;
    try {
      execution = await _functions.createExecution(
        functionId: AppwriteConfig.authFunctionId,
        body: jsonEncode({'action': action, ...payload}),
        xasync: false,
        method: ExecutionMethod.pOST,
        headers: {'content-type': 'application/json'},
      );
    } on aw.AppwriteException catch (e) {
      throw toAuthBackendException(e);
    }

    final body = _decode(execution.responseBody);
    final status = execution.responseStatusCode;
    if (status >= 400) {
      throw toAuthBackendException(
        aw.AppwriteException(
          body['message']?.toString(),
          status,
          body['type']?.toString(),
          execution.responseBody,
        ),
      );
    }
    if (execution.status.name != 'completed') {
      // A cold-start timeout or a crash leaves no response at all. It must
      // not read as a successful registration.
      throw const AuthBackendException(
        AuthFailure.network,
        code: 'function_incomplete',
        message: 'The auth Function did not complete',
      );
    }
    return body;
  }

  static Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return const {};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : {'value': decoded};
    } on FormatException {
      return {'message': body};
    }
  }
}
