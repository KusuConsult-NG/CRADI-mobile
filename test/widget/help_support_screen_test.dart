import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:climate_app/features/settings/screens/help_support_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:climate_app/l10n/app_localizations.dart';

void main() {
  Widget buildScreen() {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (ctx, state) => const HelpSupportScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (ctx, state) => const SizedBox(),
        ),
      ],
    );

    return MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }

  group('HelpSupportScreen Widget Tests', () {
    testWidgets('should display app bar with title', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Help & Support'), findsOneWidget);
    });

    testWidgets('should display FAQ section header', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Frequently Asked Questions'), findsOneWidget);
    });

    testWidgets('should display all 4 FAQ items', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('How do I report a hazard?'), findsOneWidget);
      expect(find.text('What do the alert colors mean?'), findsOneWidget);
      expect(find.text('Can I report without internet?'), findsOneWidget);
      expect(find.text('How do I verify other reports?'), findsOneWidget);
    });

    testWidgets('should expand FAQ tile when tapped', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('How do I report a hazard?'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Navigate to the "Report" tab'),
        findsOneWidget,
      );
    });

    testWidgets('should display "Still need help?" section', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Still need help?'), findsOneWidget);
    });

    testWidgets('should display Contact Support button with email icon',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Contact Support'), findsOneWidget);
      expect(find.byIcon(Icons.email_outlined), findsOneWidget);
    });

    testWidgets('Contact Support button should be tappable', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      // Scroll to make sure button is visible
      await tester.scrollUntilVisible(
        find.text('Contact Support'),
        200,
      );
      // Tap the button — it calls url_launcher which may not open in test,
      // but it should not throw
      await tester.tap(find.text('Contact Support'));
      await tester.pumpAndSettle();
      // If url_launcher can't open, a SnackBar fallback is shown
      // Either way, the button is functional and no crash
    });

    testWidgets('should display back arrow icon', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
    });

    testWidgets('FAQ tiles should use ExpansionTile widgets', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.byType(ExpansionTile), findsNWidgets(4));
    });
  });
}
