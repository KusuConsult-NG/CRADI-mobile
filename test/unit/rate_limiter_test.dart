import 'dart:convert';

import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/services/rate_limiter.dart';
import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nothing exercised the brute-force throttle before: these cover the
/// lockout ladder, the OTP windows, and what the throttle does when the
/// keystore holds a value it cannot read (corrupted entry, older build) or
/// when the device clock is wrong.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final limiter = RateLimiter();
  final storage = SecureStorageService();
  final l10n = englishL10n;

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('login throttle', () {
    test('a fresh device is allowed with the full attempt budget', () async {
      final result = await limiter.checkLoginAttempt();
      expect(result.allowed, isTrue);
      expect(result.remainingAttempts, RateLimiter.maxLoginAttempts);
      expect(result.threatLevel, ThreatLevel.low);
      expect(result.threatColor, 'green');
    });

    test('the remaining budget drops with each failure', () async {
      await limiter.recordFailedLogin();
      await limiter.recordFailedLogin();
      final result = await limiter.checkLoginAttempt();
      expect(result.allowed, isTrue);
      expect(result.remainingAttempts, RateLimiter.maxLoginAttempts - 2);
      expect(result.threatLevel, ThreatLevel.low);
    });

    test('a cooldown kicks in once the threat level rises', () async {
      for (var i = 0; i < 3; i++) {
        await limiter.recordFailedLogin();
      }
      final result = await limiter.checkLoginAttempt();
      expect(result.allowed, isFalse);
      expect(result.threatLevel, ThreatLevel.medium);
      expect(result.waitDuration, isNotNull);
      expect(result.waitDuration!.inSeconds, lessThanOrEqualTo(30));
      expect(result.userMessage(l10n), isNotEmpty);
    });

    test('the cooldown lapses once enough time has passed', () async {
      for (var i = 0; i < 3; i++) {
        await limiter.recordFailedLogin();
      }
      // Pretend the last failure was an hour ago.
      await storage.write(
        'last_login_attempt',
        DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      );
      final result = await limiter.checkLoginAttempt();
      expect(result.allowed, isTrue);
      expect(result.threatLevel, ThreatLevel.medium);
    });

    test('the account locks at the attempt ceiling', () async {
      for (var i = 0; i < RateLimiter.maxLoginAttempts; i++) {
        await limiter.recordFailedLogin();
      }
      await storage.write(
        'last_login_attempt',
        DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      );

      final result = await limiter.checkLoginAttempt();
      expect(result.allowed, isFalse);
      expect(result.remainingAttempts, 0);
      expect(result.lockedUntil, isNotNull);
      expect(result.threatLevel, ThreatLevel.high);
      expect(await storage.isAccountLocked(), isTrue);

      // While locked, every further check is refused without re-locking.
      final again = await limiter.checkLoginAttempt();
      expect(again.allowed, isFalse);
      expect(again.lockedUntil, isNotNull);
    });

    test('a repeat lockout lasts longer than the first (backoff)', () async {
      Future<Duration> lockoutLength() async {
        for (var i = 0; i < RateLimiter.maxLoginAttempts; i++) {
          await limiter.recordFailedLogin();
        }
        await storage.write(
          'last_login_attempt',
          DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
        );
        final result = await limiter.checkLoginAttempt();
        final until = result.lockedUntil!;
        return until.difference(DateTime.now());
      }

      final first = await lockoutLength();
      // Clear the lock and the attempt counter but keep the lockout history.
      await storage.delete('account_locked_until');
      await storage.resetLoginAttempts();
      final second = await lockoutLength();

      expect(second.inMinutes, greaterThan(first.inMinutes));
    });

    test('a lockout never exceeds 24 hours', () async {
      await storage.write('lockout_count', '40');
      for (var i = 0; i < 12; i++) {
        await limiter.recordFailedLogin();
      }
      await storage.write(
        'last_login_attempt',
        DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      );
      final result = await limiter.checkLoginAttempt();
      final remaining = result.lockedUntil!.difference(DateTime.now());
      expect(remaining.inHours, lessThanOrEqualTo(24));
    });

    test('an expired lock clears itself and resets the counter', () async {
      await storage.lockAccount(const Duration(milliseconds: -1));
      expect(await storage.isAccountLocked(), isFalse);
      final result = await limiter.checkLoginAttempt();
      expect(result.allowed, isTrue);
      expect(result.remainingAttempts, RateLimiter.maxLoginAttempts);
    });

    test('a successful login clears the attempt history', () async {
      for (var i = 0; i < 4; i++) {
        await limiter.recordFailedLogin();
      }
      await limiter.resetLoginAttempts();
      final result = await limiter.checkLoginAttempt();
      expect(result.allowed, isTrue);
      expect(result.remainingAttempts, RateLimiter.maxLoginAttempts);
      expect(await storage.read('last_login_attempt'), isNull);
    });

    test('threat level tracks the attempt count', () async {
      Future<ThreatLevel> levelAfter(int attempts) async {
        FlutterSecureStorage.setMockInitialValues({
          'login_attempts': '$attempts',
        });
        return (await limiter.getStats())['threatLevel'] as String == ''
            ? ThreatLevel.low
            : ThreatLevel.values.byName(
                (await limiter.getStats())['threatLevel'] as String,
              );
      }

      expect(await levelAfter(0), ThreatLevel.low);
      expect(await levelAfter(2), ThreatLevel.low);
      expect(await levelAfter(4), ThreatLevel.medium);
      expect(await levelAfter(7), ThreatLevel.high);
      expect(await levelAfter(9), ThreatLevel.critical);
    });

    test('getStats reports the throttle state', () async {
      await limiter.recordFailedLogin();
      final stats = await limiter.getStats();
      expect(stats['attempts'], 1);
      expect(stats['maxAttempts'], RateLimiter.maxLoginAttempts);
      expect(stats['remainingAttempts'], RateLimiter.maxLoginAttempts - 1);
      expect(stats['isLocked'], isFalse);
      expect(stats['remainingLockTime'], isNull);
    });
  });

  group('corrupted or legacy keystore entries', () {
    test('an unparsable last-attempt timestamp does not throw', () async {
      FlutterSecureStorage.setMockInitialValues({
        'login_attempts': '3',
        'last_login_attempt': 'not-a-date',
      });
      final result = await limiter.checkLoginAttempt();
      // No cooldown can be computed, so the attempt is allowed through
      // rather than the login screen crashing.
      expect(result.allowed, isTrue);
    });

    test('an unparsable lock timestamp is dropped, not fatal', () async {
      FlutterSecureStorage.setMockInitialValues({
        'account_locked_until': '13/07/2024',
      });
      expect(await storage.isAccountLocked(), isFalse);
      expect(await storage.getAccountLockedUntil(), isNull);
      expect(await limiter.getRemainingLockTime(), isNull);
      // The unreadable entry is cleared so it cannot keep failing.
      expect(await storage.read('account_locked_until'), isNull);
    });

    test('an unparsable session expiry reads as no session', () async {
      FlutterSecureStorage.setMockInitialValues({
        'session_expiry': '¯\\_(ツ)_/¯',
      });
      expect(await storage.getSessionExpiry(), isNull);
      expect(await storage.isSessionValid(), isFalse);
    });

    test('a non-JSON OTP entry is treated as a fresh window', () async {
      FlutterSecureStorage.setMockInitialValues({
        'otp_requests_user@example.com': '{not json',
      });
      final result = await limiter.checkOtpRequest('user@example.com');
      expect(result.allowed, isTrue);
      expect(result.remainingAttempts, RateLimiter.maxOtpRequests - 1);
    });

    test('a JSON OTP entry with the wrong shape is tolerated', () async {
      FlutterSecureStorage.setMockInitialValues({
        // count as a string and no windowStart: a shape an older build
        // could have written.
        'otp_requests_user@example.com': jsonEncode({'count': '2'}),
      });
      final result = await limiter.checkOtpRequest('user@example.com');
      expect(result.allowed, isTrue);
      await limiter.recordOtpRequest('user@example.com');
      final stored = await storage.readJson('otp_requests_user@example.com');
      expect(stored, isNotNull);
      expect(stored!['count'], 1);
    });
  });

  group('OTP request window', () {
    const id = 'user@example.com';

    test('the first request is allowed', () async {
      final result = await limiter.checkOtpRequest(id);
      expect(result.allowed, isTrue);
      expect(result.remainingAttempts, RateLimiter.maxOtpRequests - 1);
    });

    test('the budget is exhausted after maxOtpRequests', () async {
      for (var i = 0; i < RateLimiter.maxOtpRequests; i++) {
        expect((await limiter.checkOtpRequest(id)).allowed, isTrue);
        await limiter.recordOtpRequest(id);
      }
      final blocked = await limiter.checkOtpRequest(id);
      expect(blocked.allowed, isFalse);
      expect(blocked.threatLevel, ThreatLevel.high);
      expect(blocked.waitDuration, isNotNull);
      expect(blocked.userMessage(l10n), isNotEmpty);
    });

    test('the window resets once it has elapsed', () async {
      final old = DateTime.now().subtract(const Duration(hours: 1));
      await storage.writeJson('otp_requests_$id', {
        'count': RateLimiter.maxOtpRequests,
        'lastRequest': old.toIso8601String(),
        'windowStart': old.toIso8601String(),
      });
      final result = await limiter.checkOtpRequest(id);
      expect(result.allowed, isTrue);
      expect(result.remainingAttempts, RateLimiter.maxOtpRequests - 1);

      // Recording after an expired window restarts the count at 1.
      await limiter.recordOtpRequest(id);
      final stored = await storage.readJson('otp_requests_$id');
      expect(stored!['count'], 1);
    });

    test('budgets are per identifier', () async {
      for (var i = 0; i < RateLimiter.maxOtpRequests; i++) {
        await limiter.recordOtpRequest(id);
      }
      expect((await limiter.checkOtpRequest(id)).allowed, isFalse);
      expect(
        (await limiter.checkOtpRequest('other@example.com')).allowed,
        isTrue,
      );
    });

    test('resetOtpRequests clears the budget', () async {
      for (var i = 0; i < RateLimiter.maxOtpRequests; i++) {
        await limiter.recordOtpRequest(id);
      }
      await limiter.resetOtpRequests(id);
      expect((await limiter.checkOtpRequest(id)).allowed, isTrue);
    });
  });

  group('OTP resend cooldown', () {
    test('the first resend is allowed', () async {
      expect((await limiter.checkOtpResend()).allowed, isTrue);
    });

    test('a second resend straight away is refused', () async {
      await limiter.recordOtpResend();
      final result = await limiter.checkOtpResend();
      expect(result.allowed, isFalse);
      expect(result.waitDuration!.inSeconds, lessThanOrEqualTo(60));
      expect(result.threatLevel, ThreatLevel.medium);
    });

    test('the cooldown lapses', () async {
      await storage.write(
        'last_otp_resend',
        DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      );
      expect((await limiter.checkOtpResend()).allowed, isTrue);
    });

    test('a clock that moved backwards keeps the user waiting', () async {
      // The stored timestamp is in the future: elapsed is negative, which
      // must not read as "cooldown already over".
      await storage.write(
        'last_otp_resend',
        DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      );
      expect((await limiter.checkOtpResend()).allowed, isFalse);
    });

    test('an unparsable resend timestamp does not throw', () async {
      await storage.write('last_otp_resend', 'yesterday');
      expect((await limiter.checkOtpResend()).allowed, isTrue);
    });
  });

  group('distributed attack detection', () {
    test('no recorded pattern is not an attack', () async {
      expect(await limiter.isDistributedAttack('+2348012345678'), isFalse);
    });

    test('enough unique devices trips the threshold', () async {
      await storage.writeJson('attack_pattern_+2348012345678', {
        'uniqueDevices': RateLimiter.distributedAttackThreshold,
      });
      expect(await limiter.isDistributedAttack('+2348012345678'), isTrue);
    });

    test('a malformed pattern entry is not an attack', () async {
      await storage.write('attack_pattern_+2348012345678', 'garbage');
      expect(await limiter.isDistributedAttack('+2348012345678'), isFalse);
    });
  });

  group('RateLimitResult messages', () {
    test('an allowed result with no attempts left says nothing', () {
      final result = RateLimitResult(allowed: true);
      expect(result.userMessage(l10n), isEmpty);
    });

    test('a refused result with no reason falls back to a generic one', () {
      final result = RateLimitResult(allowed: false);
      expect(result.userMessage(l10n), l10n.rateLimitExceeded);
    });

    test('threat colour covers every level', () {
      final colours = {
        for (final level in ThreatLevel.values)
          RateLimitResult(allowed: true, threatLevel: level).threatColor,
      };
      expect(colours.length, ThreatLevel.values.length);
    });
  });
}
