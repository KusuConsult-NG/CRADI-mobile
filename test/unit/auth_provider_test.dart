import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// AuthProvider unit tests that do not need a Supabase backend.
///
/// Email / phone verification codes are generated, sent and checked by
/// Supabase Auth (verifyOTP), so there is no client-side OTP logic left to
/// test here; these tests cover the offline / not-configured behaviour and
/// the error contracts the screens rely on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'has_completed_onboarding': true});
    FlutterSecureStorage.setMockInitialValues({
      // Plaintext credentials written by older builds must be purged.
      'user_email': 'old@test.com',
      'user_password': 'hunter2',
    });
  });

  group('AuthProvider without a configured backend', () {
    test('initializes as signed out', () async {
      final auth = AuthProvider();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(auth.isInitialized, isTrue);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.currentUser, isNull);
      expect(auth.userRole, isNull);
      expect(auth.hasCompletedOnboarding, isTrue);
    });

    test('purges legacy plaintext credentials', () async {
      AuthProvider();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      const storage = FlutterSecureStorage();
      expect(await storage.read(key: 'user_email'), isNull);
      expect(await storage.read(key: 'user_password'), isNull);
    });

    test('verifyOtpAndLogin without an email/phone context throws', () async {
      final auth = AuthProvider();
      expect(
        () => auth.verifyOtpAndLogin('123456'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.userMessage(englishL10n),
            'message',
            contains('No user context'),
          ),
        ),
      );
    });

    test('resendVerificationLink without a pending email throws', () async {
      final auth = AuthProvider();
      expect(auth.resendVerificationLink, throwsA(isA<AuthException>()));
    });
  });

  group('EmailNotConfirmedException', () {
    test('is an AuthException carrying the email', () {
      final e = EmailNotConfirmedException('a@b.com');
      expect(e, isA<AuthException>());
      expect(e.email, 'a@b.com');
      expect(e.userMessage(englishL10n), contains('a@b.com'));
    });
  });
}
