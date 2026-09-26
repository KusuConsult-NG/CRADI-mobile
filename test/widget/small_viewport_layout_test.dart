import 'dart:math' as math;

import 'package:climate_app/core/l10n/fallback_localizations.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/theme/app_theme.dart';
import 'package:climate_app/core/widgets/severity_marker.dart';
import 'package:climate_app/core/widgets/word_safe_label.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/dashboard/widgets/dashboard_stat_card.dart';
import 'package:climate_app/features/dashboard/widgets/home_feed_filter_bar.dart';
import 'package:climate_app/features/profile/widgets/biometric_login_tile.dart';
import 'package:climate_app/features/reporting/screens/my_reports_screen.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/screens/reports_status_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'reports_status_screen_test.mocks.dart';

/// Layout defects a browser pass found at 320x640 and in the four Nigerian
/// locales: labels broken in half, tab labels clipped, pills wrapping inside
/// themselves. Each test here fails on the code as it was.

/// A screen-sized host at [size], in [locale], with the system font scaled.
Widget _app(
  Widget home, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) => MaterialApp(
  theme: AppTheme.lightTheme,
  locale: locale,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: home,
);

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The width the widest single word of [paragraph] needs on one line.
double _widestWordWidth(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  final style = paragraph.text.style;
  var widest = 0.0;
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final painter = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: paragraph.textDirection,
      textScaler: paragraph.textScaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }
  return widest;
}

/// Fails when [finder]'s text had to be broken through the middle of a word
/// to fit its box ("Pendin/g").
void _expectNoMidWordBreak(WidgetTester tester, Finder finder) {
  for (final element in finder.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final widest = _widestWordWidth(paragraph);
    expect(
      paragraph.size.width + 0.5,
      greaterThanOrEqualTo(widest),
      reason:
          '"${paragraph.text.toPlainText()}" was laid out in '
          '${paragraph.size.width}px, narrower than its widest word '
          '(${widest}px), so the wrap cuts through a word',
    );
  }
}

/// Fails when a tab label is wider than the tab drawn around it, which is
/// how a non-scrollable [TabBar] clips ("Ti Fọwọ́ S…").
void _expectTabLabelsNotClipped(WidgetTester tester) {
  final tabs = find.byType(Tab);
  expect(tabs, findsWidgets);
  for (var i = 0; i < tabs.evaluate().length; i++) {
    final tab = tabs.at(i);
    final label = find.descendant(of: tab, matching: find.byType(RichText));
    expect(label, findsOneWidget, reason: 'tab $i has no label');
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(
      paragraph.size.width,
      lessThanOrEqualTo(tester.getSize(tab).width + 0.5),
      reason:
          'tab label "${paragraph.text.toPlainText()}" is wider than its tab '
          'and is clipped',
    );
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'tab label "${paragraph.text.toPlainText()}" is truncated',
    );
  }
}

void main() {
  group('Dashboard stat cards (320x640)', () {
    Widget cards() => Builder(
      builder: (context) => Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DashboardStatCard(
                count: '8',
                label: context.l10n.active,
                icon: Icons.warning_amber,
                color: Colors.amber,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DashboardStatCard(
                count: '10',
                label: context.l10n.pending,
                icon: Icons.schedule,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DashboardStatCard(
                count: '7',
                label: context.l10n.approved,
                icon: Icons.check_circle,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );

    for (final locale in const [
      Locale('en'),
      Locale('ha'),
      Locale('yo'),
      Locale('ig'),
      Locale('pcm'),
    ]) {
      testWidgets('labels are not broken mid-word in ${locale.languageCode}', (
        tester,
      ) async {
        _setViewport(tester, const Size(320, 640));
        await tester.pumpWidget(_app(cards(), locale: locale));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(WordSafeLabel), findsNWidgets(6));
        _expectNoMidWordBreak(tester, find.byType(RichText));
      });
    }

    testWidgets('survives 1.5x text scale in Yoruba', (tester) async {
      _setViewport(tester, const Size(320, 640));
      await tester.pumpWidget(
        _app(cards(), locale: const Locale('yo'), textScale: 1.5),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      _expectNoMidWordBreak(tester, find.byType(RichText));
    });
  });

  group('Home feed filter pills', () {
    Widget bar() => Builder(
      builder: (context) => Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: HomeFeedFilterBar(
            filters: [
              HomeFeedFilter(0, context.l10n.toVerify),
              HomeFeedFilter(1, context.l10n.alerts),
              HomeFeedFilter(2, context.l10n.myReports),
              HomeFeedFilter(3, context.l10n.homeTabNearby),
            ],
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    );

    for (final size in const [Size(320, 640), Size(390, 844)]) {
      for (final locale in const [Locale('ha'), Locale('yo')]) {
        testWidgets('each pill keeps its label on one line '
            '(${locale.languageCode}, ${size.width.toInt()}px)', (
          tester,
        ) async {
          _setViewport(tester, size);
          await tester.pumpWidget(_app(bar(), locale: locale, textScale: 1.5));
          await tester.pump();

          expect(tester.takeException(), isNull);
          final labels = find.descendant(
            of: find.byType(HomeFeedFilterBar),
            matching: find.byType(RichText),
          );
          expect(labels, findsNWidgets(4));
          for (final element in labels.evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            final oneLine = TextPainter(
              text: paragraph.text,
              textDirection: paragraph.textDirection,
              textScaler: paragraph.textScaler,
              maxLines: 1,
            )..layout();
            expect(
              paragraph.size.height,
              lessThanOrEqualTo(oneLine.height + 0.5),
              reason:
                  '"${paragraph.text.toPlainText()}" wrapped inside its pill',
            );
            oneLine.dispose();
          }
        });
      }
    }

    testWidgets('the row scrolls when the pills do not fit', (tester) async {
      _setViewport(tester, const Size(320, 640));
      await tester.pumpWidget(
        _app(bar(), locale: const Locale('ha'), textScale: 1.5),
      );
      await tester.pump();

      final scrollable = find.descendant(
        of: find.byType(HomeFeedFilterBar),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      // The last pill is off-screen but reachable.
      await tester.drag(scrollable, const Offset(-200, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('TabBar labels', () {
    late MockReportsStatusProvider reports;
    late MockAuthProvider auth;

    setUp(() {
      reports = MockReportsStatusProvider();
      auth = MockAuthProvider();
      when(auth.userRole).thenReturn(UserRole.user);
      when(auth.currentUser).thenReturn(null);
      when(auth.hasListeners).thenReturn(false);
      when(
        auth.canVoteOn(
          reporterId: anyNamed('reporterId'),
          reportWard: anyNamed('reportWard'),
          reportLga: anyNamed('reportLga'),
        ),
      ).thenReturn(false);
      when(
        auth.canManageReportStatus(reporterId: anyNamed('reporterId')),
      ).thenReturn(false);
      when(reports.hasListeners).thenReturn(false);
      when(
        reports.refreshReports(userId: anyNamed('userId')),
      ).thenAnswer((_) async {});
      when(
        reports.fetchAllPages(userId: anyNamed('userId')),
      ).thenAnswer((_) async {});
      when(reports.getReports(any, userId: anyNamed('userId'))).thenReturn([]);
      when(
        reports.isLoading(any, userId: anyNamed('userId')),
      ).thenReturn(false);
      when(reports.hasMore(any, userId: anyNamed('userId'))).thenReturn(false);
      when(reports.errorFor(any, userId: anyNamed('userId'))).thenReturn(null);
      when(reports.hasVotedOn(any)).thenReturn(false);
      when(
        reports.fetchReports(
          status: anyNamed('status'),
          userId: anyNamed('userId'),
          loadMore: anyNamed('loadMore'),
        ),
      ).thenAnswer((_) async {});
    });

    Widget host(Widget screen, Locale locale, double textScale) {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => screen),
          GoRoute(path: '/dashboard', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/report-view', builder: (_, _) => const SizedBox()),
          GoRoute(path: '/report/hazard', builder: (_, _) => const SizedBox()),
        ],
      );
      addTearDown(router.dispose);
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ReportsStatusProvider>.value(value: reports),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      );
    }

    for (final locale in const [
      Locale('en'),
      Locale('ha'),
      Locale('yo'),
      Locale('ig'),
      Locale('pcm'),
    ]) {
      testWidgets('the four reports-status tabs are readable in '
          '${locale.languageCode} at 320px', (tester) async {
        _setViewport(tester, const Size(320, 640));
        await tester.pumpWidget(host(const ReportsStatusScreen(), locale, 1.0));
        await tester.pump();

        expect(find.byType(Tab), findsNWidgets(4));
        expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, true);
        _expectTabLabelsNotClipped(tester);
      });
    }

    testWidgets('reports-status tabs survive 1.5x text scale in Yoruba', (
      tester,
    ) async {
      _setViewport(tester, const Size(320, 640));
      await tester.pumpWidget(
        host(const ReportsStatusScreen(), const Locale('yo'), 1.5),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      _expectTabLabelsNotClipped(tester);
    });

    testWidgets('my-reports tabs are readable in Hausa at 1.5x text scale', (
      tester,
    ) async {
      _setViewport(tester, const Size(320, 640));
      await tester.pumpWidget(
        host(const MyReportsScreen(), const Locale('ha'), 1.5),
      );
      await tester.pump();

      expect(find.byType(Tab), findsNWidgets(2));
      expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, true);
      _expectTabLabelsNotClipped(tester);
    });
  });

  group('Biometric login tile (Profile)', () {
    testWidgets('is disabled and explained when the device has none', (
      tester,
    ) async {
      var toggled = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: BiometricLoginTile(
              available: false,
              checking: false,
              enabled: false,
              onChanged: (_) => toggled++,
            ),
          ),
        ),
      );
      await tester.pump();

      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(
        tile.onChanged,
        isNull,
        reason: 'the switch must not be live without usable biometrics',
      );
      // The same explanation Settings shows.
      expect(find.text('Not available on this device'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(toggled, 0);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('is live once biometrics are available', (tester) async {
      var toggled = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: BiometricLoginTile(
              available: true,
              checking: false,
              enabled: false,
              onChanged: (_) => toggled++,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNotNull,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(toggled, 1);
    });

    testWidgets('stays disabled while the check is still running', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: BiometricLoginTile(
              available: false,
              checking: true,
              enabled: false,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      expect(find.text('Loading...'), findsOneWidget);
    });
  });

  group('Severity marker', () {
    testWidgets('is a drawn shape plus the written level, not an emoji', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: SeverityMarker(label: 'Low', color: Colors.green),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.circle), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      // Still announced as more than a colour.
      expect(find.bySemanticsLabel('Severity: Low'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('no screen prefixes a severity with an emoji', (tester) async {
      // The markers used to be 🔴🟠🟡🟢, which render as a tofu box
      // wherever no emoji font is installed.
      final emoji = RegExp(
        '[\u{1F534}\u{1F7E0}\u{1F7E1}\u{1F7E2}]',
        unicode: true,
      );
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: SeverityMarker(label: 'Critical', color: Colors.red),
          ),
        ),
      );
      await tester.pump();
      for (final element in find.byType(RichText).evaluate()) {
        final text = (element.renderObject! as RenderParagraph).text
            .toPlainText();
        expect(
          emoji.hasMatch(text),
          isFalse,
          reason: 'emoji marker in "$text"',
        );
      }
    });
  });
}
