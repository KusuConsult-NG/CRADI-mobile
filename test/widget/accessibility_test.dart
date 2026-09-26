import 'package:climate_app/core/theme/app_theme.dart';
import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/features/contacts/providers/emergency_contacts_provider.dart';
import 'package:climate_app/features/contacts/screens/emergency_contacts_screen.dart';
import 'package:climate_app/features/profile/widgets/sos_sheet.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/features/reporting/screens/hazard_selection_screen.dart';
import 'package:climate_app/features/reporting/screens/severity_selection_screen.dart';
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:climate_app/shared/widgets/custom_text_field.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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

/// A whole screen under test, with the delegates the app installs.
Widget _screen(Widget home, {double textScale = 1.0}) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: home,
);

class _FakeContactsProvider extends ChangeNotifier
    implements EmergencyContactsProvider {
  _FakeContactsProvider(this.contacts);
  final List<EmergencyContact> contacts;

  @override
  Stream<List<EmergencyContact>> getContactsStream() =>
      Stream<List<EmergencyContact>>.value(contacts);

  @override
  Future<List<EmergencyContact>> fetchContacts() async => contacts;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The first node in the semantics tree matching [test]. Some controls
/// (Slider) put their semantics on a node the widget finders do not reach.
SemanticsNode? _findNode(
  SemanticsNode node,
  bool Function(SemanticsNode) test,
) {
  if (test(node)) return node;
  SemanticsNode? found;
  node.visitChildren((child) {
    found ??= _findNode(child, test);
    return found == null;
  });
  return found;
}

EmergencyContact _contact() => EmergencyContact(
  id: 'c1',
  name: 'Amina Bello',
  role: 'Ward coordinator',
  phone: '08012345678',
  category: 'coordinator',
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

    testWidgets('while loading it announces that it is submitting', (
      tester,
    ) async {
      // The loading state replaces the label with a bare spinner, so the
      // spinner itself has to carry the message.
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
      final data = tester
          .getSemantics(find.byType(CircularProgressIndicator))
          .getSemanticsData();
      expect(data.label, 'Submitting, please wait');
      expect(data.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

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
    testWidgets('its label is part of the input\'s own semantics node', (
      tester,
    ) async {
      // The label stays a sibling Text visually, but it is merged into the
      // field's semantics node, so TalkBack/VoiceOver focusing the input
      // announce "Phone number" and not just "edit box".
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 300,
            child: CustomTextField(label: 'Phone number', hint: '0801...'),
          ),
        ),
      );
      // Still drawn once, and only once: the visible Text is excluded from
      // the semantics tree so it is not announced twice.
      expect(find.text('Phone number'), findsOneWidget);
      final data = tester
          .getSemantics(find.byType(EditableText))
          .getSemanticsData();
      expect(data.label, contains('Phone number'));
      expect(data.flagsCollection.isTextField, isTrue);
      handle.dispose();
    });

    testWidgets('an unlabelled edit box is never announced', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 300,
            child: CustomTextField(
              label: 'Describe what you can see',
              hint: 'Flooding across the main road',
            ),
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
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

  group('Emergency contacts (emergency path)', () {
    Widget host({double textScale = 1.0}) =>
        ChangeNotifierProvider<EmergencyContactsProvider>(
          create: (_) => _FakeContactsProvider([_contact()]),
          child: _screen(const EmergencyContactsScreen(), textScale: textScale),
        );

    testWidgets('the call and SMS buttons are named, not just icons', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Call Amina Bello'),
        findsOneWidget,
        reason: 'the call button must be announced by name',
      );
      expect(
        find.bySemanticsLabel('Send a text message to Amina Bello'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('every control is labelled and big enough to hit', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('still lays out at 1.5x text scale', (tester) async {
      await tester.pumpWidget(host(textScale: 1.5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Reporting: severity selection', () {
    Widget host({double textScale = 1.0}) =>
        ChangeNotifierProvider<ReportingProvider>(
          create: (_) => ReportingProvider(),
          child: _screen(const SeveritySelectionScreen(), textScale: textScale),
        );

    testWidgets('the severity slider announces the level, not a number', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // The Slider puts its semantics on a node the widget finders do not
      // reach, so it is looked up by its adjust action.
      final slider = _findNode(
        tester.binding.rootElement!.renderObject!.debugSemantics!,
        (n) => n.getSemanticsData().hasAction(SemanticsAction.increase),
      );
      expect(slider, isNotNull, reason: 'the slider must be adjustable');
      final value = slider!.getSemanticsData().value;
      expect(value, contains('Severity:'));
      expect(value, contains('Low'));
      handle.dispose();
    });

    testWidgets('the chosen severity is spoken as more than a colour', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('^Severity: ')),
        findsAtLeastNWidgets(1),
      );
      handle.dispose();
    });

    testWidgets('controls meet the tap-target and labelling guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('survives 1.5x text scale', (tester) async {
      await tester.pumpWidget(host(textScale: 1.5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Reporting: hazard selection', () {
    Widget host({double textScale = 1.0}) =>
        ChangeNotifierProvider<ReportingProvider>(
          create: (_) => ReportingProvider(),
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            routerConfig: GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => const HazardSelectionScreen(),
                ),
                GoRoute(
                  path: '/dashboard',
                  builder: (_, _) => const SizedBox(),
                ),
                GoRoute(
                  path: '/report/severity',
                  builder: (_, _) => const SizedBox(),
                ),
              ],
            ),
          ),
        );

    testWidgets('the hazard cards are buttons with a selected state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      final flooding = find.text('Flooding');
      expect(flooding, findsOneWidget);
      var data = tester.getSemantics(flooding).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isSelected, Tristate.isFalse);

      await tester.tap(flooding);
      await tester.pumpAndSettle();
      data = tester.getSemantics(find.text('Flooding')).getSemanticsData();
      expect(
        data.flagsCollection.isSelected,
        Tristate.isTrue,
        reason: 'selection is otherwise only a border colour and a checkmark',
      );
      handle.dispose();
    });

    testWidgets('every control is named and large enough', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('lays out at 1.5x text scale', (tester) async {
      await tester.pumpWidget(host(textScale: 1.5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
