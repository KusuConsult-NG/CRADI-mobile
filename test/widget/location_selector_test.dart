import 'package:climate_app/core/widgets/location_selector_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LocationSelectorWidget shows only focal states', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationSelectorWidget(
            onLocationChanged: (state, lga, ward) {},
          ),
        ),
      ),
    );

    // Find State dropdown
    final stateDropdown = find.text('Select State');
    expect(stateDropdown, findsOneWidget);

    // Tap to open
    await tester.tap(stateDropdown);
    await tester.pumpAndSettle();

    // Check for focal states
    expect(find.text('Plateau'), findsOneWidget);
    expect(find.text('Benue'), findsOneWidget);
    expect(find.text('Nasarawa'), findsOneWidget);

    // Check that other states are NOT present (e.g. Lagos, Kano)
    expect(find.text('Lagos'), findsNothing);
    expect(find.text('Kano'), findsNothing);
  });

  testWidgets('LGA dropdown enables after state selection', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocationSelectorWidget(
            onLocationChanged: (state, lga, ward) {},
          ),
        ),
      ),
    );

    // Initially LGA should be disabled/hint "Select state first"
    expect(find.text('Select state first'), findsOneWidget);

    // Select State
    await tester.tap(find.text('Select State'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plateau').last); // Select Plateau
    await tester.pumpAndSettle();

    // Now LGA hint should change to "Select LGA"
    expect(find.text('Select LGA'), findsOneWidget);
    expect(find.text('Select state first'), findsNothing);

    // Open LGA dropdown
    await tester.tap(find.text('Select LGA'));
    await tester.pumpAndSettle();

    // Check specific LGAs for Plateau
    expect(find.text('Jos North'), findsOneWidget);
    expect(find.text('Jos South'), findsOneWidget);
  });
}
