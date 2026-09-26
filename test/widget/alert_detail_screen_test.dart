import 'package:climate_app/features/alerts/screens/alert_detail_screen.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:climate_app/l10n/app_localizations.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'has_completed_onboarding': true});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Widget buildScreen(Map<String, dynamic> alert) {
    // Opened directly (as from a notification): nothing to pop.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => AlertDetailScreen(alert: alert),
        ),
        GoRoute(
          path: '/alerts',
          builder: (context, state) => const Scaffold(body: Text('ALERTS')),
        ),
      ],
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<ReportsStatusProvider>(
          create: (_) => ReportsStatusProvider(),
        ),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
  }

  testWidgets('renders a staff-created alert row', (tester) async {
    await tester.pumpWidget(
      buildScreen({
        'id': 'a1',
        'title': 'Flood warning',
        'message': 'River levels rising in Bama.',
        'severity': 'high',
        'targetLga': 'Bama',
        'isActive': true,
        'createdAt': '2026-09-01T10:00:00Z',
      }),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Flood warning'), findsOneWidget);
    expect(find.text('River levels rising in Bama.'), findsOneWidget);
    expect(find.text('Bama'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    // No report behind it: no peer-verification section.
    expect(find.text('Peer Verification Required'), findsNothing);
  });

  testWidgets('shows the staff alert severity as its label', (tester) async {
    await tester.pumpWidget(
      buildScreen({'title': 'Storm', 'severity': 'critical'}),
    );
    await tester.pump();
    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('Normal Severity'), findsNothing);
  });

  testWidgets('tolerates an empty map', (tester) async {
    await tester.pumpWidget(buildScreen(const {}));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Alert'), findsOneWidget);
  });

  testWidgets('dismiss without a back stack goes to the alerts list', (
    tester,
  ) async {
    await tester.pumpWidget(buildScreen({'title': 'X'}));
    await tester.pump();
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('ALERTS'), findsOneWidget);
  });
}
