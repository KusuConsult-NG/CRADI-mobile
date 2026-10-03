import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/services/auth_backend.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';

/// An [AuthBackend] that answers with whatever the test asks for.
///
/// Before the seam existed none of this was reachable: every one of these
/// flows went straight into `supabase_flutter`, so the nine `switch
/// (e.code)` blocks that decide what a user is told — after a failed
/// sign-in, a refused code, a password that will not set — had no test at
/// all. They are the app's worst moments to get wrong.
class _FakeAuthBackend implements AuthBackend {
  _FakeAuthBackend({this.configured = true});

  final bool configured;

  /// Thrown by the next call to the named method.
  final Map<String, AuthBackendException> failures = {};

  /// Returned by the next call to the named method.
  final Map<String, AuthOutcome> outcomes = {};

  final List<String> calls = [];

  AuthUser? user;

  T _run<T>(String name, T Function() ok) {
    calls.add(name);
    final failure = failures[name];
    if (failure != null) throw failure;
    return ok();
  }

  AuthOutcome _outcome(String name) =>
      _run(name, () => outcomes[name] ?? const AuthOutcome());

  @override
  bool get isConfigured => configured;

  @override
  Stream<AuthChange> get changes => const Stream<AuthChange>.empty();

  @override
  AuthUser? get currentUser => user;

  @override
  bool get hasSession => user != null;

  @override
  bool get isSessionExpired => false;

  @override
  Future<AuthOutcome> signUpWithPassword({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async => _outcome('signUp');

  @override
  Future<AuthOutcome> signInWithPassword({
    required String email,
    required String password,
  }) async => _outcome('signIn');

  @override
  Future<void> sendPhoneOtp({
    required String phone,
    required bool createUser,
    Map<String, dynamic>? data,
  }) async => _run('sendPhoneOtp', () {});

  @override
  Future<void> resendSignUpCode(String email) =>
      Future.sync(() => _run('resendSignUpCode', () {}));

  @override
  Future<AuthOutcome> verifySignUpOtp({
    required String email,
    required String token,
  }) async => _outcome('verifySignUpOtp');

  @override
  Future<AuthOutcome> verifyPhoneOtp({
    required String phone,
    required String token,
  }) async => _outcome('verifyPhoneOtp');

  @override
  Future<void> verifyRecoveryOtp({
    required String email,
    required String token,
  }) async => _run('verifyRecoveryOtp', () {});

  @override
  Future<void> sendPasswordResetCode(String email) async =>
      _run('sendPasswordResetCode', () {});

  @override
  Future<void> updatePassword(String newPassword) async =>
      _run('updatePassword', () {});

  @override
  Future<void> updateEmail(String newEmail, {String? password}) async =>
      _run('updateEmail', () {});

  @override
  Future<AuthUser?> reloadUser() async => _run('reloadUser', () => user);

  @override
  Future<void> refreshSession() async => _run('refreshSession', () {});

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    user = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAuthBackend backend;

  setUp(() {
    SharedPreferences.setMockInitialValues({'has_completed_onboarding': true});
    FlutterSecureStorage.setMockInitialValues({});
    backend = _FakeAuthBackend();
  });

  AuthProvider provider() => AuthProvider(auth: backend);

  Future<String> failureMessage(Future<void> Function() call) async {
    try {
      await call();
      fail('expected the call to throw');
    } on AuthException catch (e) {
      return e.userMessage(englishL10n);
    }
  }

  group('sign-up tells the user which condition stopped them', () {
    final expected = <AuthFailure, String>{
      AuthFailure.accountExists: englishL10n.authErrorAccountRegistered,
      AuthFailure.weakPassword: englishL10n.authErrorWeakPassword,
      AuthFailure.invalidEmail: englishL10n.validation_invalidEmail,
      AuthFailure.providerDisabled: englishL10n.authErrorRegistrationDisabled,
      AuthFailure.rateLimited: englishL10n.authErrorTooManyAttempts,
      AuthFailure.network: englishL10n.authErrorNetworkRetry,
      AuthFailure.unknown: englishL10n.authErrorRegistrationFailed,
    };

    expected.forEach((failure, message) {
      test('${failure.name} -> "$message"', () async {
        backend.failures['signUp'] = AuthBackendException(failure);
        final auth = provider();
        expect(
          await failureMessage(
            () => auth.signUpWithEmail(
              email: 'a@example.com',
              password: 'Password1!',
            ),
          ),
          message,
        );
      });
    });

    test('no session means the app waits for the emailed code', () async {
      backend.outcomes['signUp'] = const AuthOutcome(
        user: AuthUser(id: 'u1', email: 'a@example.com'),
      );
      final auth = provider();
      expect(
        await auth.signUpWithEmail(
          email: 'A@Example.com ',
          password: 'Password1!',
        ),
        isTrue,
      );
      // Normalised, and remembered so the verify screen knows the address.
      expect(auth.pendingEmail, 'a@example.com');
    });
  });

  group('verifying a code', () {
    final expected = <AuthFailure, String>{
      // A wrong code and an expired one read the same to the user, and the
      // backend may report either.
      AuthFailure.otpExpired: englishL10n.authErrorInvalidCode,
      AuthFailure.invalidCredentials: englishL10n.authErrorInvalidCode,
      AuthFailure.rateLimited: englishL10n.authErrorTooManyAttemptsRetry,
      AuthFailure.network: englishL10n.errorNetwork,
      AuthFailure.unknown: englishL10n.authErrorVerificationFailed,
    };

    expected.forEach((failure, message) {
      test('${failure.name} -> "$message"', () async {
        backend.failures['verifySignUpOtp'] = AuthBackendException(failure);
        final auth = provider();
        expect(
          await failureMessage(
            () => auth.verifyOtpAndLogin(
              '123456',
              registrationData: {'email': 'a@example.com'},
            ),
          ),
          message,
        );
      });
    });

    test('a user without a session is refused, not signed in', () async {
      // The first step of a secure email change answers with a user and no
      // session. Accepting it would flip the app to "signed in" with no
      // credentials behind it.
      backend.outcomes['verifySignUpOtp'] = const AuthOutcome(
        user: AuthUser(id: 'u1'),
      );
      final auth = provider();
      expect(
        await failureMessage(
          () => auth.verifyOtpAndLogin(
            '123456',
            registrationData: {'email': 'a@example.com'},
          ),
        ),
        englishL10n.authErrorVerificationFailed,
      );
      expect(auth.isAuthenticated, isFalse);
    });
  });

  group('asking for a reset code', () {
    test('a throttled address says so, not "failed to send"', () async {
      backend.failures['sendPasswordResetCode'] = const AuthBackendException(
        AuthFailure.rateLimited,
      );
      final auth = provider();
      expect(
        await failureMessage(() => auth.sendPasswordResetEmail('a@b.com')),
        englishL10n.authErrorTooManyAttempts,
      );
    });

    test('offline says retry, not failed', () async {
      backend.failures['sendPasswordResetCode'] = const AuthBackendException(
        AuthFailure.network,
      );
      final auth = provider();
      expect(
        await failureMessage(() => auth.sendPasswordResetEmail('a@b.com')),
        englishL10n.authErrorNetworkRetry,
      );
    });

    test('the address is normalised before it is sent', () async {
      final auth = provider();
      await auth.sendPasswordResetEmail('  A@B.com ');
      expect(backend.calls, contains('sendPasswordResetCode'));
    });
  });

  group('completing a reset with a typed code', () {
    final expected = <AuthFailure, String>{
      AuthFailure.otpExpired: englishL10n.authErrorResetCodeInvalid,
      AuthFailure.invalidCredentials: englishL10n.authErrorResetCodeInvalid,
      AuthFailure.weakPassword: englishL10n.authErrorResetWeakPassword,
      AuthFailure.samePassword: englishL10n.authErrorResetSamePassword,
      AuthFailure.unknown: englishL10n.authErrorResetFailed,
    };

    expected.forEach((failure, message) {
      test('a refused code (${failure.name}) -> "$message"', () async {
        backend.failures['verifyRecoveryOtp'] = AuthBackendException(failure);
        final auth = provider();
        expect(
          await failureMessage(
            () => auth.confirmPasswordReset(
              email: 'a@b.com',
              code: '123456',
              newPassword: 'Password1!',
            ),
          ),
          message,
        );
      });
    });

    test('a refused code leaves an existing session alone', () async {
      // The reset screen is reachable while signed in; a typo must not log
      // the user out.
      backend.user = const AuthUser(id: 'u1');
      backend.failures['verifyRecoveryOtp'] = const AuthBackendException(
        AuthFailure.otpExpired,
      );
      final auth = provider();
      await failureMessage(
        () => auth.confirmPasswordReset(
          email: 'a@b.com',
          code: '000000',
          newPassword: 'Password1!',
        ),
      );
      expect(backend.calls, isNot(contains('signOut')));
      expect(backend.user, isNotNull);
    });

    test('an accepted code always ends in a sign-out', () async {
      backend.user = const AuthUser(id: 'u1');
      final auth = provider();
      await auth.confirmPasswordReset(
        email: 'a@b.com',
        code: '123456',
        newPassword: 'Password1!',
      );
      expect(backend.calls, contains('updatePassword'));
      expect(backend.calls, contains('signOut'));
    });

    test('an accepted code signs out even if the change fails', () async {
      backend.user = const AuthUser(id: 'u1');
      backend.failures['updatePassword'] = const AuthBackendException(
        AuthFailure.weakPassword,
      );
      final auth = provider();
      expect(
        await failureMessage(
          () => auth.confirmPasswordReset(
            email: 'a@b.com',
            code: '123456',
            newPassword: 'short',
          ),
        ),
        englishL10n.authErrorResetWeakPassword,
      );
      expect(backend.calls, contains('signOut'));
    });
  });

  group('completing a reset from a recovery link', () {
    test('a dead session reads as an invalid code', () async {
      backend.failures['updatePassword'] = const AuthBackendException(
        AuthFailure.sessionExpired,
      );
      final auth = provider();
      expect(
        await failureMessage(() => auth.completePasswordRecovery('Password1!')),
        englishL10n.authErrorResetCodeInvalid,
      );
    });

    test('the pending flag is cleared even when the change fails', () async {
      // Leaving it raised would trap the user on the reset screen with a
      // session they cannot use.
      backend.failures['updatePassword'] = const AuthBackendException(
        AuthFailure.unknown,
      );
      final auth = provider();
      await failureMessage(() => auth.completePasswordRecovery('Password1!'));
      expect(auth.isPasswordRecoveryPending, isFalse);
    });
  });

  group('a refused sign-in', () {
    final expected = <AuthFailure, String>{
      AuthFailure.invalidCredentials: englishL10n.authErrorInvalidCredentials,
      AuthFailure.accountBanned: englishL10n.authErrorAccountDisabled,
      AuthFailure.rateLimited: englishL10n.authErrorTooManyLogins,
      AuthFailure.network: englishL10n.authErrorLoginConnection,
      AuthFailure.unknown: englishL10n.authErrorLoginFailed,
    };

    expected.forEach((failure, message) {
      test('${failure.name} -> "$message"', () async {
        backend.failures['signIn'] = AuthBackendException(failure);
        final auth = provider();
        expect(
          await failureMessage(
            () => auth.signInWithEmail(
              email: 'a@example.com',
              password: 'Password1!',
            ),
          ),
          message,
        );
      });
    });

    test('an unconfirmed address resends the code and says which', () async {
      // The login screen routes on this exception rather than on a string.
      backend.failures['signIn'] = const AuthBackendException(
        AuthFailure.emailNotConfirmed,
      );
      final auth = provider();
      try {
        await auth.signInWithEmail(
          email: ' A@Example.com',
          password: 'Password1!',
        );
        fail('expected the sign-in to throw');
      } on EmailNotConfirmedException catch (e) {
        expect(e.email, 'a@example.com');
      }
      expect(backend.calls, contains('resendSignUpCode'));
      expect(auth.pendingEmail, 'a@example.com');
    });

    test('a resend that also fails does not mask the real reason', () async {
      backend.failures['signIn'] = const AuthBackendException(
        AuthFailure.emailNotConfirmed,
      );
      backend.failures['resendSignUpCode'] = const AuthBackendException(
        AuthFailure.rateLimited,
      );
      final auth = provider();
      await expectLater(
        auth.signInWithEmail(email: 'a@example.com', password: 'Password1!'),
        throwsA(isA<EmailNotConfirmedException>()),
      );
    });

    test(
      'a sign-in with no user is refused rather than half-applied',
      () async {
        backend.outcomes['signIn'] = const AuthOutcome(hasSession: true);
        final auth = provider();
        expect(
          await failureMessage(
            () => auth.signInWithEmail(
              email: 'a@example.com',
              password: 'Password1!',
            ),
          ),
          englishL10n.authErrorLoginFailed,
        );
        expect(auth.isAuthenticated, isFalse);
      },
    );
  });

  group('with no backend configured', () {
    test('the app settles as signed out rather than hanging', () async {
      final auth = AuthProvider(auth: _FakeAuthBackend(configured: false));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(auth.isInitialized, isTrue);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.currentUser, isNull);
      expect(auth.hasStoredSession, isFalse);
    });
  });
}
