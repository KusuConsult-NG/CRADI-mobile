import 'dart:ui' show SemanticsAction;
import 'package:climate_app/core/theme/app_theme.dart';
import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/features/profile/widgets/sos_sheet.dart';
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/shared/widgets/custom_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Accessibility is not covered anywhere else. For an emergency app the
/// floor is: every control a screen reader can name, tap targets a shaking
/// hand can hit, and text that still fits when the system font is scaled up.
Widget _host(Widget child, {double textScale = 1.0}) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(body: Center(child: child)),
  ),
);

String? _requireNumber(String? value) =>
    (value == null || value.isEmpty) ? 'Enter a valid Nigerian number' : null;

void main() {
  group('CustomButton', () {
    testWidgets('is announced by its label and is tappable', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 200,
            child: CustomButton(text: 'Submit report', onPressed: () => taps++),
          ),
        ),
      );

      final data = tester
          .getSemantics(find.text('Submit report'))
          .getSemanticsData();
      expect(data.label, 'Submit report');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      await tester.tap(find.text('Submit report'));
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('meets the Android tap-target size', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 200,
            child: CustomButton(text: 'Report a hazard', onPressed: () {}),
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('a disabled button is not reported as tappable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 200,
            child: CustomButton(text: 'Submit report'),
          ),
        ),
      );
      final data = tester
          .getSemantics(find.text('Submit report'))
          .getSemanticsData();
      expect(data.label, 'Submit report');
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });

    testWidgets(
      'while loading it shows a spinner that a screen reader cannot name',
      (tester) async {
        // Documented gap: the loading state replaces the label with a bare
        // CircularProgressIndicator, so a screen-reader user is told
        // nothing about what the button is doing. Fixing this means adding
        // a Semantics label to the spinner.
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(
            const SizedBox(
              width: 200,
              child: CustomButton(text: 'Submit report', isLoading: true),
            ),
          ),
        );
        expect(find.text('Submit report'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('the label still fits at 2x text scale', (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 250,
            child: CustomButton(text: 'Report a hazard', onPressed: () {}),
          ),
          textScale: 2.0,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('CustomTextField', () {
    testWidgets('its label is a sibling Text, not part of the field node', (
      tester,
    ) async {
      // Documented gap: the label is drawn above the field rather than
      // passed as InputDecoration.labelText, so the field's own semantics
      // node is unlabelled. TalkBack/VoiceOver focusing the input
      // announces only "edit box" plus the hint, never "Phone number".
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 300,
            child: CustomTextField(label: 'Phone number', hint: '0801...'),
          ),
        ),
      );
      expect(find.text('Phone number'), findsOneWidget);
      final node = tester.getSemantics(find.byType(EditableText));
      expect(node.label, isNot(contains('Phone number')));
      handle.dispose();
    });

    testWidgets('a validation error is rendered as text, not colour alone', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final key = GlobalKey<FormState>();
      await tester.pumpWidget(
        _host(
          Form(
            key: key,
            child: const SizedBox(
              width: 300,
              child: CustomTextField(
                label: 'Phone number',
                validator: _requireNumber,
              ),
            ),
          ),
        ),
      );
      key.currentState!.validate();
      await tester.pump();
      // The error must exist as its own text node, so the status is not
      // conveyed by the red border alone.
      expect(find.text('Enter a valid Nigerian number'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an obscured field is marked as such', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 300,
            child: CustomTextField(label: 'Password', obscureText: true),
          ),
        ),
      );
      final flags = tester
          .getSemantics(find.byType(EditableText))
          .getSemanticsData()
          .flagsCollection;
      expect(flags.isObscured, isTrue);
      expect(flags.isTextField, isTrue);
      handle.dispose();
    });

    testWidgets('survives 2x text scale without overflowing', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 300,
            child: CustomTextField(
              label: 'Describe what you can see',
              hint: 'Flooding across the main road',
            ),
          ),
          textScale: 2.0,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('SOS contacts (emergency path)', () {
    Future<List<EmergencyContact>> empty() async => const [];

    testWidgets('every control is reachable and labelled', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) =>
                SosContactsList(load: empty, hostContext: context),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('the error state is readable at 1.5x text scale', (
      tester,
    ) async {
      Future<List<EmergencyContact>> failing() async =>
          throw Exception('offline');
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) =>
                SosContactsList(load: failing, hostContext: context),
          ),
          textScale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining("Couldn't load your contacts"),
        findsOneWidget,
      );
    });
  });
}
