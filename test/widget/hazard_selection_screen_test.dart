import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/features/reporting/screens/hazard_selection_screen.dart';

/// Widget tests for Hazard Selection Screen
///
/// Tests hazard type selection, UI rendering, and navigation
void main() {
  group('HazardSelectionScreen Widget Tests', () {
    Widget createHazardSelectionScreen() {
      return const MaterialApp(home: HazardSelectionScreen());
    }

    testWidgets('should display app bar with title', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createHazardSelectionScreen());

      expect(find.text('Select Hazard'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('should display instruction text', (WidgetTester tester) async {
      await tester.pumpWidget(createHazardSelectionScreen());

      expect(
        find.text('What type of incident are you reporting?'),
        findsOneWidget,
      );
    });

    testWidgets('should display hazard cards', (WidgetTester tester) async {
      await tester.pumpWidget(createHazardSelectionScreen());

      // Should have first few hazard types visible
      expect(find.text('Flooding'), findsOneWidget);
      expect(find.text('Extreme Heat'), findsOneWidget);
      expect(find.text('Drought'), findsOneWidget);
      expect(find.text('Windstorms'), findsOneWidget);

      // Note: Some cards may be off-screen in test viewport
      // Scrolling would be needed to see all 8
    });

    testWidgets('continue button should be disabled initially', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createHazardSelectionScreen());

      final continueButton = find.widgetWithText(ElevatedButton, 'Continue');
      expect(continueButton, findsOneWidget);

      final button = tester.widget<ElevatedButton>(continueButton);
      expect(button.onPressed, isNull); // Disabled
    });

    testWidgets('should select hazard when tapped', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createHazardSelectionScreen());

      // Tap on first hazard (Flooding)
      await tester.tap(find.text('Flooding'));
      await tester.pump();

      // Continue button should now be enabled
      final continueButton = find.widgetWithText(ElevatedButton, 'Continue');
      final button = tester.widget<ElevatedButton>(continueButton);
      expect(button.onPressed, isNotNull); // Enabled
    });

    testWidgets('should show selection checkmark on selected hazard', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(createHazardSelectionScreen());

      // Tap on Flooding
      await tester.tap(find.text('Flooding'));
      await tester.pump();

      // Should show check icon (one for the checkmark bubble)
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('should allow changing selection', (WidgetTester tester) async {
      await tester.pumpWidget(createHazardSelectionScreen());

      // Select first hazard
      await tester.tap(find.text('Flooding'));
      await tester.pump();

      // Select different hazard (one that's visible)
      await tester.tap(find.text('Extreme Heat'));
      await tester.pump();

      // Still only one checkmark (for the newly selected item)
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('should display hazard icons', (WidgetTester tester) async {
      await tester.pumpWidget(createHazardSelectionScreen());

      // Check that Icon widgets are present
      final icons = find.byType(Icon);
      expect(icons, findsWidgets);

      // Should have multiple icons visible
      expect(icons.evaluate().length, greaterThan(2));
    });

    testWidgets('should render in grid layout', (WidgetTester tester) async {
      await tester.pumpWidget(createHazardSelectionScreen());

      // Find the GridView
      expect(find.byType(GridView), findsOneWidget);
    });

    // TODO: Add tests for:
    // - Navigation to location picker on continue
    // - Scrolling to see all 8 hazards
    // - Visual feedback for selected state
    // - Accessibility features
  });
}
