import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/features/reporting/screens/hazard_selection_screen.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:climate_app/l10n/app_localizations.dart';

import 'hazard_selection_screen_test.mocks.dart';

@GenerateMocks([ReportingProvider])
void main() {
  late MockReportingProvider mockProvider;

  setUp(() {
    mockProvider = MockReportingProvider();
    // Stub out the reset() called in initState postFrameCallback
    when(mockProvider.reset()).thenReturn(null);
    when(mockProvider.setHazardType(any)).thenReturn(null);
    // ChangeNotifier stubs
    when(mockProvider.hasListeners).thenReturn(false);
    when(mockProvider.isLoading).thenReturn(false);
  });

  GoRouter buildRouter() => GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (ctx, state) => const HazardSelectionScreen(),
      ),
      GoRoute(path: '/dashboard', builder: (ctx, state) => const SizedBox()),
      GoRoute(
        path: '/report/severity',
        builder: (ctx, state) => const SizedBox(),
      ),
    ],
  );

  Widget buildScreen() => ChangeNotifierProvider<ReportingProvider>.value(
    value: mockProvider,
    child: MaterialApp.router(
      routerConfig: buildRouter(),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );

  group('HazardSelectionScreen Widget Tests', () {
    testWidgets('should display app bar with title', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Select Hazard'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('should display instruction text', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(
        find.text('What type of incident are you reporting?'),
        findsOneWidget,
      );
    });

    testWidgets('should display hazard cards', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.text('Flooding'), findsOneWidget);
      expect(find.text('Drought'), findsOneWidget);
    });

    testWidgets('continue button should be disabled initially', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      final continueButton = find.widgetWithText(ElevatedButton, 'Continue');
      expect(continueButton, findsOneWidget);
      final button = tester.widget<ElevatedButton>(continueButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('should select hazard when tapped', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flooding'));
      await tester.pump();
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Continue'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('should show selection checkmark on selected hazard', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flooding'));
      await tester.pump();
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('should allow changing selection', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flooding'));
      await tester.pump();
      await tester.tap(find.text('Drought'));
      await tester.pump();
      // Only one checkmark regardless of current selection
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('should display hazard icons', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.byType(Icon), findsWidgets);
      expect(find.byType(Icon).evaluate().length, greaterThan(2));
    });

    testWidgets('should render in grid layout', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
    });
  });
}
