import 'package:climate_app/core/l10n/fallback_localizations.dart';
import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:climate_app/core/widgets/force_update_gate.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/widgets/report_vote_actions.dart';
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'reports_status_screen_test.mocks.dart';

void main() {
  group('Hausa locale', () {
    testWidgets('Material widgets work and app strings are Hausa', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ha'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              ctx = context;
              return Scaffold(
                appBar: AppBar(title: const Text('x')),
                body: const TextField(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(Localizations.localeOf(ctx), const Locale('ha'));
      expect(MaterialLocalizations.of(ctx).okButtonLabel, 'OK');
      expect(AppLocalizations.of(ctx)!.localeName, 'ha');

      // A dialog needs MaterialLocalizations (barrier label etc.).
      showDialog<void>(
        context: ctx,
        builder: (_) => const AlertDialog(content: Text('hi')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('hi'), findsOneWidget);
    });
  });

  group('ReportVoteActions', () {
    late MockReportsStatusProvider reports;
    late MockAuthProvider auth;

    VerificationReport report({ReportStatus status = ReportStatus.pending}) =>
        VerificationReport(
          id: 'r1',
          title: 'Flood',
          type: 'Flood',
          reporter: 'Someone',
          reporterId: 'other',
          location: 'Ward A',
          time: 'now',
          status: status,
          iconName: 'warning',
          iconColor: 'orange',
          bgIconColor: 'orange',
          ward: 'Ward A',
          lga: 'Jos South',
        );

    setUp(() {
      reports = MockReportsStatusProvider();
      auth = MockAuthProvider();
      when(reports.hasListeners).thenReturn(false);
      when(auth.hasListeners).thenReturn(false);
      when(reports.hasVotedOn(any)).thenReturn(false);
      when(
        auth.canVoteOn(
          reporterId: anyNamed('reporterId'),
          reportWard: anyNamed('reportWard'),
          reportLga: anyNamed('reportLga'),
        ),
      ).thenReturn(true);
      when(
        reports.verifyReport(
          any,
          userId: anyNamed('userId'),
          comment: anyNamed('comment'),
        ),
      ).thenAnswer((_) async {});
      when(
        reports.disputeReport(
          any,
          userId: anyNamed('userId'),
          comment: anyNamed('comment'),
        ),
      ).thenAnswer((_) async {});
    });

    Widget build(VerificationReport r) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ReportsStatusProvider>.value(value: reports),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(
        home: Scaffold(body: ReportVoteActions(report: r)),
      ),
    );

    testWidgets('shown to an eligible voter on a pending report', (
      tester,
    ) async {
      await tester.pumpWidget(build(report()));
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Dispute'), findsOneWidget);
    });

    testWidgets('hidden when not pending, already voted, or not allowed', (
      tester,
    ) async {
      await tester.pumpWidget(build(report(status: ReportStatus.verified)));
      expect(find.text('Confirm'), findsNothing);

      when(reports.hasVotedOn('r1')).thenReturn(true);
      await tester.pumpWidget(build(report()));
      expect(find.text('Confirm'), findsNothing);

      when(reports.hasVotedOn('r1')).thenReturn(false);
      when(
        auth.canVoteOn(
          reporterId: anyNamed('reporterId'),
          reportWard: anyNamed('reportWard'),
          reportLga: anyNamed('reportLga'),
        ),
      ).thenReturn(false);
      await tester.pumpWidget(build(report()));
      expect(find.text('Confirm'), findsNothing);
    });

    testWidgets('Confirm casts a confirming vote', (tester) async {
      await tester.pumpWidget(build(report()));
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      verify(reports.verifyReport('r1')).called(1);
      expect(find.text('Report confirmed. Thank you!'), findsOneWidget);
    });

    testWidgets('Dispute requires a comment and passes it on', (tester) async {
      await tester.pumpWidget(build(report()));
      await tester.tap(find.text('Dispute'));
      await tester.pumpAndSettle();
      // Empty comment: the dialog stays open.
      await tester.tap(find.widgetWithText(TextButton, 'Dispute'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Not flooded');
      await tester.tap(find.widgetWithText(TextButton, 'Dispute'));
      await tester.pumpAndSettle();
      verify(reports.disputeReport('r1', comment: 'Not flooded')).called(1);
      expect(
        find.text('Dispute recorded. Staff will review the report.'),
        findsOneWidget,
      );
    });

    testWidgets('a refused vote shows the reason', (tester) async {
      when(
        reports.verifyReport(
          any,
          userId: anyNamed('userId'),
          comment: anyNamed('comment'),
        ),
      ).thenThrow(const VerificationRefusedException('Already voted'));
      await tester.pumpWidget(build(report()));
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Already voted'), findsOneWidget);
    });

    testWidgets('loads the user\'s votes when shown', (tester) async {
      await tester.pumpWidget(build(report()));
      verify(reports.loadMyVotes()).called(1);
    });

    testWidgets('hides the buttons once the report is no longer pending', (
      tester,
    ) async {
      when(
        reports.verifyReport(
          any,
          userId: anyNamed('userId'),
          comment: anyNamed('comment'),
        ),
      ).thenThrow(
        const VerificationRefusedException(
          'Already decided',
          noLongerPending: true,
        ),
      );
      await tester.pumpWidget(build(report()));
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Already decided'), findsOneWidget);
      expect(find.text('Confirm'), findsNothing);
    });
  });

  group('ForceUpdateGate', () {
    tearDown(() {
      RemoteConfigService()
        ..debugSetValues({})
        ..debugSetCurrentVersion(null);
    });

    testWidgets('blocks the app below app_min_version', (tester) async {
      final cfg = RemoteConfigService()..debugSetCurrentVersion('1.0.14');
      await tester.pumpWidget(
        const MaterialApp(home: ForceUpdateGate(child: Text('app body'))),
      );
      expect(find.text('app body'), findsOneWidget);

      cfg.debugSetValues({'app_min_version': '9.0.0'});
      await tester.pump();
      expect(find.text('app body'), findsNothing);
      expect(find.text('Update required'), findsOneWidget);
    });

    testWidgets('offers a store link on Android only', (tester) async {
      RemoteConfigService()
        ..debugSetCurrentVersion('1.0.0')
        ..debugSetValues({'app_min_version': '9.0.0'});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(
          const MaterialApp(home: ForceUpdateGate(child: Text('app body'))),
        );
        expect(find.text('Update'), findsOneWidget);
        expect(
          ForceUpdateGate.storeUri().toString(),
          'https://play.google.com/store/apps/details?id='
          'com.westgatestratagem.climate_app.climate_app',
        );

        // No App Store id exists: no button on iOS.
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        await tester.pumpWidget(
          const MaterialApp(
            home: ForceUpdateGate(key: ValueKey('ios'), child: Text('x')),
          ),
        );
        expect(find.text('Update'), findsNothing);
        expect(find.text('Check again'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
