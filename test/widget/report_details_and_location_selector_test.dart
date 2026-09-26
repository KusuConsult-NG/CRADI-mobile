import 'package:climate_app/core/providers/language_provider.dart';
import 'package:climate_app/core/widgets/location_selector_widget.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/features/reporting/screens/report_details_screen.dart';
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLanguageProvider extends ChangeNotifier implements LanguageProvider {
  @override
  String get selectedLanguage => 'English';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'ReportDetailsScreen opened again (review "Edit") keeps the description',
    (tester) async {
      final reporting = ReportingProvider()
        ..setDescription("Water didn't recede & roads closed");
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const ReportDetailsScreen()),
          GoRoute(path: '/report/review', builder: (_, _) => const SizedBox()),
        ],
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ReportingProvider>.value(value: reporting),
            ChangeNotifierProvider<LanguageProvider>(
              create: (_) => _FakeLanguageProvider(),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, "Water didn't recede & roads closed");
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('LocationSelectorWidget treats blank/unknown initial values as '
      'unselected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: LocationSelectorWidget(
              initialState: '',
              initialLGA: 'Nowhere',
              initialWard: '',
              onLocationChanged: (_, _, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Select State'), findsOneWidget);
    expect(find.text('Select State first'), findsOneWidget);
  });

  testWidgets('LocationSelectorWidget keeps a valid initial state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: LocationSelectorWidget(
              initialState: 'Atlantis',
              onLocationChanged: (_, _, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Select State'), findsOneWidget);
  });
}
