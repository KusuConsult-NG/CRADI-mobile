import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/auth/screens/reset_password_screen.dart';
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The reset screen has two shapes, and which one it shows is the whole
/// difference between "type the code you were emailed" and "the link already
/// signed you in, just pick a password".
///
/// Before this, the link in the recovery mail was built from the project's
/// Site URL — the admin panel — so app users who tapped it were asked to sign
/// in to a staff portal they have no account for. The app now claims that
/// link; these pin what it renders once it has.
Future<void> _pump(WidgetTester tester, {required bool recovery}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ResetPasswordScreen(hasRecoverySession: recovery),
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

  testWidgets('the code flow asks for the email and the code', (tester) async {
    await _pump(tester, recovery: false);

    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Reset Code'), findsOneWidget);
    expect(find.text('New Password'), findsOneWidget);
  });

  testWidgets('an opened link asks for the password and nothing else', (
    tester,
  ) async {
    await _pump(tester, recovery: true);

    // Nothing left to ask: the session already identifies the user, and there
    // is no second code to type.
    expect(find.text('Email Address'), findsNothing);
    expect(find.text('Reset Code'), findsNothing);
    expect(find.text('New Password'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
  });

  testWidgets('and says so, rather than telling the user to find a code', (
    tester,
  ) async {
    await _pump(tester, recovery: true);
    expect(find.textContaining('code'), findsNothing);
  });
}
