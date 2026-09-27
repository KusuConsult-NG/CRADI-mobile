import 'dart:async';
import 'dart:io';

import 'package:climate_app/core/services/notification_service.dart';
import 'package:climate_app/features/notifications/screens/notifications_screen.dart';
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A history entry is only worth showing if it takes you to what it is about.
/// Unit tests cover `notificationRouteFor`, but computing a route is not the
/// same as the row being tappable across its whole surface, which is what the
/// browser tour found wanting.
void main() {
  late Directory dir;
  late Box<Map> box;
  late NotificationService service;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('notif_open');
    Hive.init(dir.path);
    box = await Hive.openBox<Map>('notifications_history_open');
  });

  tearDownAll(() {
    // Not awaited: the tap leaves a Hive write in flight that a fake-clock
    // widget test can never settle, and awaiting the box here would block
    // the run on it. The box lives in a temp directory, so letting the
    // process end with it open costs nothing.
    unawaited(box.close());
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows/CI can hold the file briefly; the temp dir is disposable.
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    service = NotificationService();
    service.attachHistoryBoxForTesting(box);
    await service.clearAll();
    await service.resetSeenStateForTesting();
    await service.setUserForTesting('user-a');
  });

  /// One approved-report entry, shown on the real screen; returns where a tap
  /// at [point] within the row's rect took us.
  Future<String?> tapEntryAt(
    WidgetTester tester,
    Offset Function(Rect) point,
  ) async {
    // SharedPreferences and Hive are real async; testWidgets runs under a
    // fake clock, so awaiting them outside runAsync never completes.
    await tester.runAsync(() async {
      await service.recordOwnReportStatuses([
        {'id': 'r1', 'status': 'pending', 'hazard_type': 'Flooding'},
      ]);
      await service.recordOwnReportStatuses([
        {'id': 'r1', 'status': 'approved', 'hazard_type': 'Flooding'},
      ]);
    });

    String? landed;
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (context, state) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/report/:id',
          builder: (context, state) {
            landed = '/report/${state.pathParameters['id']}';
            return const Scaffold(body: Text('REPORT'));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final card = find.byType(InkWell).first;
    await tester.tapAt(point(tester.getRect(card)));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return landed;
  }

  testWidgets('tapping the centre of an entry opens its report', (
    tester,
  ) async {
    expect(await tapEntryAt(tester, (r) => r.center), '/report/r1');
  });
}
