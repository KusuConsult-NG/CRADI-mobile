import 'dart:ui' show Locale;
import 'dart:io';

import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/utils/error_handler.dart' as eh;
import 'package:flutter_test/flutter_test.dart';

/// The release-mode message scrubber decides what a user sees when
/// something fails mid-flow. Nothing covered it before, partly because the
/// release path is unreachable from a test binary — [eh.ErrorHandler.genericMessage]
/// and [eh.ErrorHandler.sanitizeForLog] are now called directly.
void main() {
  final l10n = englishL10n;

  group('genericMessage (what a user sees in a release build)', () {
    test("the app's own exceptions keep their curated text", () {
      final e = eh.ValidationException((l) => l.commonUnknown);
      expect(eh.ErrorHandler.genericMessage(e, l10n), l10n.commonUnknown);
    });

    test('a network failure reads as a network problem', () {
      for (final e in [
        const SocketException('Failed host lookup'),
        Exception('Connection closed before full header was received'),
        Exception('NETWORK unreachable'),
      ]) {
        expect(eh.ErrorHandler.genericMessage(e, l10n), l10n.errorNetwork);
      }
    });

    test('a permission failure reads as a permission problem', () {
      expect(
        eh.ErrorHandler.genericMessage(Exception('permission denied'), l10n),
        l10n.errorNoPermission,
      );
    });

    test('an internal SDK error is scrubbed to a support message', () {
      expect(
        eh.ErrorHandler.genericMessage(Exception('Internal Error 500'), l10n),
        l10n.errorContactSupport,
      );
    });

    test('anything else falls back to the generic message', () {
      expect(
        eh.ErrorHandler.genericMessage(Exception('kaboom'), l10n),
        l10n.errorUnexpected,
      );
      expect(
        eh.ErrorHandler.genericMessage('a bare string', l10n),
        l10n.errorUnexpected,
      );
      expect(eh.ErrorHandler.genericMessage(null, l10n), l10n.errorUnexpected);
    });

    test('the message follows the chosen language', () {
      final ha = lookupAppLocalizations(const Locale('ha'));
      expect(
        eh.ErrorHandler.genericMessage(Exception('kaboom'), ha),
        ha.errorUnexpected,
      );
    });
  });

  group('sanitizeForLog', () {
    test('bearer tokens are redacted', () {
      final out = eh.ErrorHandler.sanitizeForLog(
        'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.abc-def',
      );
      expect(out, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(out, contains('REDACTED'));
    });

    test('passwords and secrets are redacted', () {
      final out = eh.ErrorHandler.sanitizeForLog(
        'login failed password=hunter2 secret: s3cr3t',
      );
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('s3cr3t')));
    });

    test('api keys are redacted', () {
      final out = eh.ErrorHandler.sanitizeForLog('api_key=sb_live_abc123');
      expect(out, isNot(contains('sb_live_abc123')));
    });

    test('phone numbers are replaced', () {
      final out = eh.ErrorHandler.sanitizeForLog(
        'OTP send failed for +2348012345678',
      );
      expect(out, isNot(contains('2348012345678')));
      expect(out, contains('[PHONE]'));
    });

    test('email addresses are replaced', () {
      final out = eh.ErrorHandler.sanitizeForLog(
        'no profile for ada.lovelace+test@example.co.uk',
      );
      expect(out, isNot(contains('ada.lovelace')));
      expect(out, contains('[EMAIL]'));
    });

    test('an ordinary message is left alone', () {
      const msg = 'Report submission failed: server unavailable';
      expect(eh.ErrorHandler.sanitizeForLog(msg), msg);
    });

    test('an empty string is handled', () {
      expect(eh.ErrorHandler.sanitizeForLog(''), '');
    });

    test('several secrets in one line are all redacted', () {
      final out = eh.ErrorHandler.sanitizeForLog(
        'user ada@example.com token: abc123 phone +2348012345678',
      );
      expect(out, isNot(contains('ada@example.com')));
      expect(out, isNot(contains('abc123')));
      expect(out, isNot(contains('2348012345678')));
    });
  });

  group('SecureException hierarchy', () {
    test('every subtype carries a localised message', () {
      final exceptions = <eh.SecureException>[
        eh.AuthException((l) => l.errorNetwork),
        eh.ValidationException((l) => l.errorNetwork),
        eh.StorageException((l) => l.errorNetwork),
      ];
      for (final e in exceptions) {
        expect(e.userMessage(l10n), l10n.errorNetwork);
      }
    });

    test('englishMessage is always English, whatever the UI locale', () {
      final e = eh.ValidationException((l) => l.errorNetwork);
      expect(e.englishMessage, englishL10n.errorNetwork);
    });

    test('EmailNotConfirmedException carries the address it re-sent to', () {
      final e = eh.EmailNotConfirmedException('ada@example.com');
      expect(e.email, 'ada@example.com');
      expect(e, isA<eh.AuthException>());
      expect(e.userMessage(l10n), contains('ada@example.com'));
    });

    test('toString includes the technical detail in debug builds', () {
      final e = eh.SecureException(
        (l) => l.errorNetwork,
        technicalDetails: 'socket 104',
      );
      expect(e.toString(), contains('socket 104'));
    });

    test('toString without details is just the message', () {
      final e = eh.SecureException((l) => l.errorNetwork);
      expect(e.toString(), englishL10n.errorNetwork);
    });
  });

  group('handleError', () {
    test('returns a user-facing message and never throws', () {
      expect(
        eh.ErrorHandler.handleError(
          Exception('kaboom'),
          l10n,
          context: 'submitReport',
        ),
        isNotEmpty,
      );
      expect(
        eh.ErrorHandler.handleError(
          eh.StorageException((l) => l.errorNetwork),
          l10n,
        ),
        l10n.errorNetwork,
      );
    });

    test('logError tolerates a null stack trace and a non-Exception', () {
      expect(
        () => eh.ErrorHandler.logError('plain string', context: 'ctx'),
        returnsNormally,
      );
      expect(
        () => eh.ErrorHandler.logError(
          Exception('x'),
          stackTrace: StackTrace.current,
        ),
        returnsNormally,
      );
    });
  });
}
