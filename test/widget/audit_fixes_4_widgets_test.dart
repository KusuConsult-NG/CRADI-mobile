import 'package:climate_app/core/services/peer_verification_service.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/widgets/dispute_comment_dialog.dart';
import 'package:climate_app/features/verification/widgets/report_response_actions.dart';
import 'package:climate_app/features/verification/widgets/report_staff_actions.dart';
import 'package:climate_app/features/verification/widgets/report_verifications_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'reports_status_screen_test.mocks.dart';
import 'package:climate_app/l10n/app_localizations.dart';

VerificationReport _report(
  ReportStatus status, {
  ResponseStatus response = ResponseStatus.awaiting,
}) => VerificationReport(
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
  responseStatus: response,
);

void main() {
  late MockReportsStatusProvider reports;
  late MockAuthProvider auth;

  setUp(() {
    reports = MockReportsStatusProvider();
    auth = MockAuthProvider();
    when(reports.hasListeners).thenReturn(false);
    when(auth.hasListeners).thenReturn(false);
    when(auth.currentUser).thenReturn(null);
  });

  Widget wrap(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider<ReportsStatusProvider>.value(value: reports),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  group('ReportResponseActions', () {
    testWidgets('says nothing when nobody has responded and you cannot', (
      tester,
    ) async {
      // An "Awaiting response" card on every report is noise.
      when(auth.canUpdateResponseStatus).thenReturn(false);
      await tester.pumpWidget(
        wrap(
          ReportResponseActions(
            report: _report(ReportStatus.pending),
            onChanged: () async {},
          ),
        ),
      );
      expect(find.text('Response'), findsNothing);
    });

    testWidgets('shows the status read-only once it has moved', (tester) async {
      // Knowing a team is on the way is useful to the reporter too.
      when(auth.canUpdateResponseStatus).thenReturn(false);
      await tester.pumpWidget(
        wrap(
          ReportResponseActions(
            report: _report(
              ReportStatus.pending,
              response: ResponseStatus.dispatched,
            ),
            onChanged: () async {},
          ),
        ),
      );
      expect(find.text('Response'), findsOneWidget);
      expect(find.text('Team dispatched'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('a responder moves it, and the screen re-fetches', (
      tester,
    ) async {
      when(auth.canUpdateResponseStatus).thenReturn(true);
      when(reports.updateResponseStatus(any, any)).thenAnswer((_) async {});
      var reloaded = false;
      await tester.pumpWidget(
        wrap(
          ReportResponseActions(
            report: _report(ReportStatus.pending),
            onChanged: () async => reloaded = true,
          ),
        ),
      );
      expect(find.byType(ChoiceChip), findsNWidgets(4));

      await tester.tap(find.text('Team dispatched'));
      await tester.pumpAndSettle();

      verify(
        reports.updateResponseStatus('r1', ResponseStatus.dispatched),
      ).called(1);
      expect(reloaded, isTrue);
    });

    testWidgets('tapping the status it already has writes nothing', (
      tester,
    ) async {
      when(auth.canUpdateResponseStatus).thenReturn(true);
      await tester.pumpWidget(
        wrap(
          ReportResponseActions(
            report: _report(
              ReportStatus.pending,
              response: ResponseStatus.resolved,
            ),
            onChanged: () async {},
          ),
        ),
      );
      await tester.tap(find.text('Resolved'));
      await tester.pumpAndSettle();
      verifyNever(reports.updateResponseStatus(any, any));
    });
  });

  group('ReportStaffActions', () {
    testWidgets('hidden for users who may not manage status', (tester) async {
      when(
        auth.canManageReportStatus(reporterId: anyNamed('reporterId')),
      ).thenReturn(false);
      await tester.pumpWidget(
        wrap(
          ReportStaffActions(
            report: _report(ReportStatus.verified),
            onChanged: () async {},
          ),
        ),
      );
      expect(find.text('Staff actions'), findsNothing);
    });

    testWidgets('approve re-fetches the report', (tester) async {
      when(
        auth.canManageReportStatus(reporterId: anyNamed('reporterId')),
      ).thenReturn(true);
      when(reports.approveReport(any)).thenAnswer((_) async {});
      var reloaded = 0;
      await tester.pumpWidget(
        wrap(
          ReportStaffActions(
            report: _report(ReportStatus.verified),
            onChanged: () async => reloaded++,
          ),
        ),
      );
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Reopen'), findsOneWidget);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      verify(reports.approveReport('r1')).called(1);
      expect(reloaded, 1);
    });

    testWidgets('reject requires a reason', (tester) async {
      when(
        auth.canManageReportStatus(reporterId: anyNamed('reporterId')),
      ).thenReturn(true);
      when(
        reports.staffRejectReport(any, reason: anyNamed('reason')),
      ).thenAnswer((_) async {});
      await tester.pumpWidget(
        wrap(
          ReportStaffActions(
            report: _report(ReportStatus.pending),
            onChanged: () async {},
          ),
        ),
      );
      expect(find.text('Approve'), findsNothing);
      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Reject'));
      await tester.pumpAndSettle();
      expect(find.text('Please give a reason.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Duplicate');
      await tester.tap(find.widgetWithText(TextButton, 'Reject'));
      await tester.pumpAndSettle();
      verify(reports.staffRejectReport('r1', reason: 'Duplicate')).called(1);
    });
  });

  group('ReportVerificationsSection', () {
    testWidgets('lists confirmations and disputes with comments', (
      tester,
    ) async {
      when(auth.userRole).thenReturn(UserRole.ewv);
      await tester.pumpWidget(
        wrap(
          ReportVerificationsSection(
            reportId: 'r1',
            loader: (_) async => const [
              ReportVerification(verifierId: 'a', isConfirmed: true),
              ReportVerification(
                verifierId: 'b',
                isConfirmed: false,
                comment: 'Road is dry',
                verifierName: 'Bola',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 confirmed · 1 disputed'), findsOneWidget);
      expect(find.text('Road is dry'), findsOneWidget);
      expect(find.textContaining('Disputed by Bola'), findsOneWidget);
    });

    testWidgets('hidden for plain users', (tester) async {
      when(auth.userRole).thenReturn(UserRole.user);
      var loads = 0;
      await tester.pumpWidget(
        wrap(
          ReportVerificationsSection(
            reportId: 'r1',
            loader: (_) async {
              loads++;
              return const [];
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Peer verifications'), findsNothing);
      expect(loads, 0);
    });
  });

  testWidgets('dispute dialog refuses an empty comment', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showDisputeCommentDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Dispute'));
    await tester.pumpAndSettle();
    expect(
      find.text('Please explain why you dispute this report.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '  Wrong ward  ');
    await tester.tap(find.widgetWithText(TextButton, 'Dispute'));
    await tester.pumpAndSettle();
    expect(result, 'Wrong ward');
  });
}
