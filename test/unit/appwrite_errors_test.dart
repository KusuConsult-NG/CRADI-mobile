import 'package:appwrite/appwrite.dart' show AppwriteException;
import 'package:flutter_test/flutter_test.dart';

import 'package:climate_app/core/services/appwrite/appwrite_errors.dart';
import 'package:climate_app/core/services/auth_backend.dart';
import 'package:climate_app/core/services/backend_failure.dart';

/// The Appwrite half of the two error tables. The Postgres half decides
/// what a user is told; this one decides the same thing, plus — through
/// `isAppwritePermanent` — whether a field agent's queued report is tried
/// again or marked rejected and never sent.
void main() {
  AppwriteException ex(String? type, [int code = 400, String? message]) =>
      AppwriteException(message ?? 'boom', code, type);

  group('data refusals', () {
    const cases = <String, BackendFailure>{
      'user_unauthorized': BackendFailure.refused,
      'general_access_forbidden': BackendFailure.refused,
      'general_rate_limit_exceeded': BackendFailure.rateLimited,
      'document_not_found': BackendFailure.notFound,
      'document_already_exists': BackendFailure.duplicate,
      'storage_file_already_exists': BackendFailure.duplicate,
      'document_invalid_structure': BackendFailure.constraint,
    };
    cases.forEach((type, expected) {
      test('$type -> ${expected.name}', () {
        expect(classifyAppwriteFailure(ex(type)), expected);
      });
    });

    test('a Function refusal has no type, so the status decides', () {
      // Phase 4's write Function answers 403 for a disabled account and
      // 409 for a replay, with no Appwrite error type at all.
      expect(classifyAppwriteFailure(ex(null, 403)), BackendFailure.refused);
      expect(classifyAppwriteFailure(ex(null, 409)), BackendFailure.duplicate);
      expect(classifyAppwriteFailure(ex(null, 404)), BackendFailure.notFound);
      expect(
        classifyAppwriteFailure(ex(null, 429)),
        BackendFailure.rateLimited,
      );
    });

    test('a bare 400 is unknown, not a constraint', () {
      // Appwrite uses 400 for a malformed request as well as a rejected
      // value. Reading a client bug as a permanent data refusal would
      // drop the queued report instead of retrying it after the fix.
      expect(classifyAppwriteFailure(ex(null, 400)), BackendFailure.unknown);
      expect(isAppwritePermanent(ex(null, 400)), isFalse);
    });

    test('something that is not an Appwrite error is not guessed at', () {
      expect(
        classifyAppwriteFailure(Exception('nope')),
        BackendFailure.unknown,
      );
      expect(isAppwritePermanent(Exception('nope')), isFalse);
      expect(isAppwriteTransient(Exception('nope')), isFalse);
    });
  });

  group('retry policy — the one that can lose a report', () {
    test('transport failure and server trouble are transient', () {
      expect(isAppwriteTransient(ex(null, 0)), isTrue);
      expect(isAppwriteTransient(ex(null, 500)), isTrue);
      expect(isAppwriteTransient(ex(null, 503)), isTrue);
      expect(
        isAppwriteTransient(ex('general_rate_limit_exceeded', 429)),
        isTrue,
      );
    });

    test('a rate limit is never permanent', () {
      // It is the clearest case of "retrying can change the answer", and
      // marking it permanent would throw the report away for being early.
      expect(
        isAppwritePermanent(ex('general_rate_limit_exceeded', 429)),
        isFalse,
      );
    });

    test('a refusal and a constraint are permanent', () {
      expect(isAppwritePermanent(ex('user_unauthorized', 401)), isTrue);
      expect(isAppwritePermanent(ex('document_invalid_structure')), isTrue);
    });

    test('a duplicate stops the queue, because the write already landed', () {
      expect(isAppwritePermanent(ex('document_already_exists', 409)), isTrue);
    });

    test('not-found is not permanent', () {
      // A document the write depends on may not exist *yet* — the profile
      // row is created by a Function that may still be running.
      expect(isAppwritePermanent(ex('document_not_found', 404)), isFalse);
    });

    test('nothing is both transient and permanent', () {
      for (final e in [
        ex(null, 0),
        ex(null, 500),
        ex('general_rate_limit_exceeded', 429),
        ex('user_unauthorized', 401),
        ex('document_already_exists', 409),
        ex(null, 400),
      ]) {
        expect(
          isAppwriteTransient(e) && isAppwritePermanent(e),
          isFalse,
          reason: '${e.type} ${e.code}',
        );
      }
    });
  });

  group('what the user is shown', () {
    test('a rate limit shows the server wording', () {
      expect(
        appwriteMessage(
          ex('general_rate_limit_exceeded', 429, 'Try again in 60 seconds'),
        ),
        'Try again in 60 seconds',
      );
    });

    test("a Function's own refusal is written for a person, so it shows", () {
      expect(
        appwriteMessage(ex(null, 403, 'Your account has been disabled')),
        'Your account has been disabled',
      );
    });

    test("Appwrite's own generic wording is not shown", () {
      expect(
        appwriteMessage(
          ex(
            'document_not_found',
            404,
            'Document with the requested ID could not be found.',
          ),
        ),
        isNull,
      );
    });

    test('the diagnostic keeps everything, for the record', () {
      final d = appwriteDiagnostic(ex('user_unauthorized', 401, 'nope'));
      expect(d, contains('401'));
      expect(d, contains('user_unauthorized'));
      expect(d, contains('nope'));
    });
  });

  group('auth conditions', () {
    const cases = <String, AuthFailure>{
      'user_invalid_credentials': AuthFailure.invalidCredentials,
      'user_not_found': AuthFailure.invalidCredentials,
      'user_unverified': AuthFailure.emailNotConfirmed,
      'user_already_exists': AuthFailure.accountExists,
      'user_email_already_exists': AuthFailure.accountExists,
      'user_blocked': AuthFailure.accountBanned,
      'user_email_not_valid': AuthFailure.invalidEmail,
      'general_smtp_disabled': AuthFailure.providerDisabled,
      'general_rate_limit_exceeded': AuthFailure.rateLimited,
      'user_invalid_token': AuthFailure.otpExpired,
      'password_recently_used': AuthFailure.weakPassword,
      'user_password_mismatch': AuthFailure.samePassword,
      'user_session_not_found': AuthFailure.sessionExpired,
      'user_jwt_invalid': AuthFailure.sessionExpired,
    };
    cases.forEach((type, expected) {
      test('$type -> ${expected.name}', () {
        expect(classifyAppwriteAuthFailure(ex(type)), expected);
      });
    });

    test('a transport failure is network, which is never a sign-out', () {
      // The session check keeps a cached session alive on `network` and
      // signs the user out on anything else, so a flaky connection must
      // not read as an invalid session.
      expect(classifyAppwriteAuthFailure(ex(null, 0)), AuthFailure.network);
      expect(classifyAppwriteAuthFailure(ex(null, 502)), AuthFailure.network);
    });

    test('an unlisted type falls through to unknown, not to a guess', () {
      expect(
        classifyAppwriteAuthFailure(ex('type_added_next_year', 418)),
        AuthFailure.unknown,
      );
    });

    test('the wrapper keeps the server wording for the log', () {
      final e = toAuthBackendException(ex('user_blocked', 401, 'blocked'));
      expect(e.failure, AuthFailure.accountBanned);
      expect(e.code, 'user_blocked');
      expect(e.message, 'blocked');
    });
  });
}
