import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'package:climate_app/core/services/auth_backend.dart';
import 'package:climate_app/core/services/supabase_auth_backend.dart';

/// The auth seam: `AuthProvider` branched on GoTrue's string error codes in
/// nine places. Those codes now stop at the adapter, and this is the table
/// that says what each one means. Every code below is one the app handled
/// in production before the swap — if a mapping silently changes, a user
/// gets the wrong sentence at the worst possible moment (a failed sign-in,
/// a password reset that will not complete).
void main() {
  AuthFailure failureOf(String code) =>
      SupabaseAuthBackend.translate(sb.AuthException('x', code: code)).failure;

  group('GoTrue codes translate to app conditions', () {
    const cases = <String, AuthFailure>{
      'invalid_credentials': AuthFailure.invalidCredentials,
      'user_not_found': AuthFailure.invalidCredentials,
      'email_not_confirmed': AuthFailure.emailNotConfirmed,
      'user_already_exists': AuthFailure.accountExists,
      'email_exists': AuthFailure.accountExists,
      'phone_exists': AuthFailure.accountExists,
      'user_banned': AuthFailure.accountBanned,
      'email_address_invalid': AuthFailure.invalidEmail,
      'validation_failed': AuthFailure.invalidEmail,
      'signup_disabled': AuthFailure.providerDisabled,
      'email_provider_disabled': AuthFailure.providerDisabled,
      'phone_provider_disabled': AuthFailure.providerDisabled,
      'sms_send_failed': AuthFailure.deliveryFailed,
      'otp_disabled': AuthFailure.otpDisabled,
      'over_email_send_rate_limit': AuthFailure.rateLimited,
      'over_sms_send_rate_limit': AuthFailure.rateLimited,
      'over_request_rate_limit': AuthFailure.rateLimited,
      'otp_expired': AuthFailure.otpExpired,
      'weak_password': AuthFailure.weakPassword,
      'same_password': AuthFailure.samePassword,
      'session_not_found': AuthFailure.sessionExpired,
      'bad_jwt': AuthFailure.sessionExpired,
      'reauthentication_needed': AuthFailure.reauthenticationNeeded,
    };

    cases.forEach((code, expected) {
      test('$code -> ${expected.name}', () {
        expect(failureOf(code), expected);
      });
    });

    test('an unknown code is never guessed at', () {
      expect(failureOf('some_code_added_next_year'), AuthFailure.unknown);
      expect(failureOf(''), AuthFailure.unknown);
    });

    test('a null code is unknown, not a crash', () {
      expect(
        SupabaseAuthBackend.translate(const sb.AuthException('boom')).failure,
        AuthFailure.unknown,
      );
    });
  });

  group('the two exception subtypes outrank the code', () {
    test('a transport failure is network, whatever code it carries', () {
      // This is the one that must not be mistaken for an answer: the
      // session check keeps a cached session alive on `network` and signs
      // the user out on anything else.
      final e = sb.AuthRetryableFetchException(message: 'no route');
      expect(SupabaseAuthBackend.translate(e).failure, AuthFailure.network);
    });

    test('a weak-password exception is recognised without the code', () {
      final e = sb.AuthWeakPasswordException(
        message: 'too short',
        statusCode: '422',
        reasons: ['length'],
      );
      expect(
        SupabaseAuthBackend.translate(e).failure,
        AuthFailure.weakPassword,
      );
    });
  });

  test('the server wording is kept for the log, not for control flow', () {
    final e = SupabaseAuthBackend.translate(
      const sb.AuthException(
        'Email not confirmed',
        code: 'email_not_confirmed',
      ),
    );
    expect(e.code, 'email_not_confirmed');
    expect(e.message, 'Email not confirmed');
    expect(e.toString(), contains('emailNotConfirmed'));
  });

  group('AuthUser', () {
    test('maps GoTrue timestamps, which are strings', () {
      final user = SupabaseAuthBackend.toAuthUser(
        const sb.User(
          id: 'u1',
          appMetadata: {},
          userMetadata: {'name': 'Amina'},
          aud: 'authenticated',
          createdAt: '2026-01-05T10:00:00Z',
          email: 'a@example.com',
          emailConfirmedAt: '2026-01-06T11:00:00Z',
        ),
      )!;

      expect(user.id, 'u1');
      expect(user.email, 'a@example.com');
      expect(user.createdAt, DateTime.utc(2026, 1, 5, 10));
      expect(user.emailConfirmedAt, DateTime.utc(2026, 1, 6, 11));
      expect(user.phoneConfirmedAt, isNull);
      expect(user.metadataName, 'Amina');
    });

    test('isConfirmed is true once either address is confirmed', () {
      expect(const AuthUser(id: 'u').isConfirmed, isFalse);
      expect(
        AuthUser(id: 'u', emailConfirmedAt: DateTime(2026)).isConfirmed,
        isTrue,
      );
      expect(
        AuthUser(id: 'u', phoneConfirmedAt: DateTime(2026)).isConfirmed,
        isTrue,
      );
    });

    test('a blank or missing metadata name reads as absent', () {
      expect(const AuthUser(id: 'u').metadataName, isNull);
      expect(
        const AuthUser(id: 'u', metadata: {'name': '   '}).metadataName,
        isNull,
      );
      expect(
        const AuthUser(id: 'u', metadata: {'name': 42}).metadataName,
        isNull,
      );
    });

    test('null maps to null', () {
      expect(SupabaseAuthBackend.toAuthUser(null), isNull);
    });
  });
}
