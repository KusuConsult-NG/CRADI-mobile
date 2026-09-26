import 'package:climate_app/core/l10n/fallback_localizations.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/auth/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The sign-in screen must not overflow on a small (320x640) phone with
/// enlarged text in Hausa (one of the longest translations).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'has_completed_onboarding': true});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('login screen does not overflow at 320x640, ha, text x1.3', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = AuthProvider();
    final router = GoRouter(
      initialLocation: '/login',
      routes: [GoRoute(path: '/login', builder: (_, _) => const LoginScreen())],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ha'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
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
    expect(find.byType(LoginScreen), findsOneWidget);
    // The email form (Remember me / Forgot password row) is shown.
    expect(find.byType(Checkbox), findsOneWidget);

    // Let AuthProvider's initialization timeout elapse.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 15));
  });
}
