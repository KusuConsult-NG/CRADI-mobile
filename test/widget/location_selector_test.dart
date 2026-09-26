import 'package:climate_app/core/widgets/location_selector_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/l10n/app_localizations.dart';

void main() {
  testWidgets('LocationSelectorWidget shows only focal states', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LocationSelectorWidget(
            onLocationChanged: (state, lga, ward) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Find State dropdown hint
    expect(find.text('Select State'), findsOneWidget);

    // Tap the dropdown — use gesture since it may overlap other widgets
    await tester.tap(find.text('Select State'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Check for focal states
    expect(find.text('Plateau'), findsWidgets);
    expect(find.text('Benue'), findsWidgets);
    expect(find.text('Nasarawa'), findsWidgets);

    // Non-focal states should not appear
    expect(find.text('Lagos'), findsNothing);
    expect(find.text('Kano'), findsNothing);
  });

  testWidgets('LGA dropdown enables after state selection', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LocationSelectorWidget(
            onLocationChanged: (state, lga, ward) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Initially LGA should show disabled hint
    expect(find.text('Select State first'), findsOneWidget);

    // Open State dropdown
    await tester.tap(find.text('Select State'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Select Plateau (use .last to pick from the dropdown list, not the button)
    await tester.tap(find.text('Plateau').last);
    await tester.pumpAndSettle();

    // Now LGA hint should change
    expect(find.text('Select LGA'), findsOneWidget);
    expect(find.text('Select State first'), findsNothing);

    // Open LGA dropdown
    await tester.tap(find.text('Select LGA'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Check Plateau LGAs
    expect(find.text('Jos North'), findsWidgets);
    expect(find.text('Jos South'), findsWidgets);
  });
}
