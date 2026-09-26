import 'package:climate_app/core/l10n/fallback_localizations.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/features/reporting/screens/report_review_screen.dart';
import 'package:climate_app/features/reporting/screens/severity_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// "Edit" on the review screen opens a wizard step whose Continue returns
/// to the review, instead of stacking a second copy of the wizard.
void main() {
  test('review edit locations are flagged', () {
    expect(reviewEditLocation('severity'), '/report/severity?edit=review');
    expect(isReviewEdit(Uri.parse(reviewEditLocation('location'))), isTrue);
    expect(isReviewEdit(Uri.parse('/report/severity')), isFalse);
  });

  Future<GoRouter> pumpWizard(WidgetTester tester, ReportingProvider p) async {
    final router = GoRouter(
      initialLocation: '/report/review',
      routes: [
        GoRoute(
          path: '/report/review',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(reviewEditLocation('severity')),
              child: const Text('REVIEW'),
            ),
          ),
        ),
        GoRoute(
          path: '/report/severity',
          builder: (_, state) =>
              SeveritySelectionScreen(returnToReview: isReviewEdit(state.uri)),
        ),
        GoRoute(
          path: '/report/location',
          builder: (_, _) => const Scaffold(body: Text('LOCATION')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ReportingProvider>.value(
        value: p,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('editing severity pops back to the single review page', (
    tester,
  ) async {
    final provider = ReportingProvider()..setSeverity('critical');
    final router = await pumpWizard(tester, provider);

    await tester.tap(find.text('REVIEW'));
    await tester.pumpAndSettle();
    expect(find.byType(SeveritySelectionScreen), findsOneWidget);

    await tester.tap(find.text(englishL10n.nextLocation));
    await tester.pumpAndSettle();

    // Back on the review page, not on a new location step.
    expect(find.text('REVIEW'), findsOneWidget);
    expect(find.text('LOCATION'), findsNothing);
    expect(find.byType(SeveritySelectionScreen), findsNothing);
    expect(router.canPop(), isFalse);
    // The step started from (and kept) the chosen severity.
    expect(provider.severity, 'critical');
  });

  testWidgets('outside review, Continue goes on to the location step', (
    tester,
  ) async {
    final router = await pumpWizard(tester, ReportingProvider());
    router.push('/report/severity');
    await tester.pumpAndSettle();
    await tester.tap(find.text(englishL10n.nextLocation));
    await tester.pumpAndSettle();
    expect(find.text('LOCATION'), findsOneWidget);
  });
}
