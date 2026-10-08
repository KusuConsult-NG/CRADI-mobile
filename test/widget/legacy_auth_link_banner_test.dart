import 'package:climate_app/core/l10n/fallback_localizations.dart';
import 'package:climate_app/core/router/app_router.dart';
import 'package:climate_app/core/services/deep_link_service.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/auth/screens/forgot_password_screen.dart';
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A user tapping a password-reset mail from the Supabase stack used to land
/// nowhere: `DeepLinkService` dropped the link and the app stayed put. It now
/// maps those links to `/forgot-password?expired=1`, and the screen explains
/// itself instead of looking like an ordinary visit.
///
/// Three seams, and only the first was covered: the mapping, the router reading
/// the query back, and the screen rendering the notice. The middle one is the
/// one that can rot in silence — `locationFor` writes the query string and
/// `isLegacyExpiredLink` reads it, from different files, with nothing
/// connecting them but the literal `expired=1`. So the mapping's own output is
/// what gets fed to the reader here, rather than a hand-written URL that would
/// agree with the reader while the producer drifted.
const _banner = Key('legacy-link-expired-banner');

Future<void> _pump(WidgetTester tester, {required bool expired}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: ForgotPasswordScreen(isLegacyExpired: expired),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'has_completed_onboarding': true});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('the mapping and the router agree', () {
    test('every legacy link the service maps reads back as expired', () {
      // The producer's output, parsed by the consumer. A typo in either
      // `expired=1` fails here and nowhere else.
      for (final link in const [
        'cradi://login-callback/#access_token=t',
        'cradi://report/r1?code=abc',
        'https://cradi.ng/reset-password?code=abc',
        'https://cradi.ng/#access_token=t&type=recovery',
        'https://cradi.ng/x?error=access_denied',
        'https://cradi.ng/x?error_code=otp_expired',
        'https://cradi.ng/x?error_description=whatever',
      ]) {
        final location = DeepLinkService.locationFor(Uri.parse(link));
        expect(location, isNotNull, reason: '$link should now be routed');
        expect(
          isLegacyExpiredLink(Uri.parse(location!)),
          isTrue,
          reason: '$link mapped to $location, which does not read as expired',
        );
      }
    });

    test('an ordinary visit to the screen is not flagged', () {
      expect(isLegacyExpiredLink(Uri.parse('/forgot-password')), isFalse);
      // Not a truthiness check: only the value the producer writes counts.
      for (final q in const ['expired=0', 'expired=', 'expired=true']) {
        expect(
          isLegacyExpiredLink(Uri.parse('/forgot-password?$q')),
          isFalse,
          reason: q,
        );
      }
    });

    test('a share link the app routes normally is untouched', () {
      final location = DeepLinkService.locationFor(
        Uri.parse('https://cradi.ng/alert/a1?utm=x'),
      );
      expect(location, '/alert/a1?utm=x');
      expect(isLegacyExpiredLink(Uri.parse(location!)), isFalse);
    });
  });

  group('the screen', () {
    testWidgets('explains itself after a dead link', (tester) async {
      await _pump(tester, expired: true);

      expect(find.byKey(_banner), findsOneWidget);
      // The localised string, not the English literal that was hard-coded
      // here: the app ships five locales and this screen is translated.
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.forgotLegacyLinkExpired), findsOneWidget);
    });

    testWidgets('says nothing extra on an ordinary visit', (tester) async {
      await _pump(tester, expired: false);

      expect(find.byKey(_banner), findsNothing);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.forgotLegacyLinkExpired), findsNothing);
      // The screen still does its actual job.
      expect(find.text(l10n.forgotSendCode), findsOneWidget);
    });

    testWidgets('the notice is translated, not English everywhere', (
      tester,
    ) async {
      // Hausa was the case that mattered: the rest of this screen is
      // translated, so an English paragraph in the middle of it is the bug.
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      final ha = await AppLocalizations.delegate.load(const Locale('ha'));
      expect(ha.forgotLegacyLinkExpired, isNot(en.forgotLegacyLinkExpired));

      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = await AppLocalizations.delegate.load(locale);
        expect(
          l10n.forgotLegacyLinkExpired.trim(),
          isNotEmpty,
          reason: 'missing translation for $locale',
        );
      }
    });
  });

  // The banner is a paragraph, and it landed on a screen that was a bare
  // `Column` with a `Spacer` and nothing scrolling — the Spacer absorbed the
  // first ~100px and the rest overflowed. Hausa and Yoruba are the long
  // translations, 320x640 is the small phone, and 1.3x is the text scale the
  // sibling test for `LoginScreen` uses.
  group('small screens', () {
    for (final locale in const [Locale('ha'), Locale('yo'), Locale('en')]) {
      testWidgets('no overflow at 320x640, $locale, x1.3', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider(),
            child: MaterialApp(
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              home: const ForgotPasswordScreen(isLegacyExpired: true),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        expect(find.byKey(_banner), findsOneWidget);

        // Let AuthProvider's initialization timeout elapse.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 15));
      });
    }
  });
}
