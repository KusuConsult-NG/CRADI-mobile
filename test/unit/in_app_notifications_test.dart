import 'dart:io';

import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/services/notification_service.dart';
import 'package:climate_app/features/alerts/providers/alerts_provider.dart';
import 'package:climate_app/features/knowledge_base/guide_bookmarks.dart';
import 'package:climate_app/features/notifications/screens/notifications_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Defect 1: the notifications history had push as its only producer, so
/// with ONESIGNAL_APP_ID unset — or simply before a push arrives — the
/// screen was empty by construction. These cover the in-app producers, the
/// shared identity that keeps push from duplicating them, and the
/// per-account / eviction rules they have to keep respecting.
///
/// Defect 2: saved guides are shared state now, not a private field of the
/// detail screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('In-app notification producers', () {
    late Directory dir;
    late Box<Map> box;
    late NotificationService service;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('in_app_notifs');
      Hive.init(dir.path);
      box = await Hive.openBox<Map>('notifications_history_in_app');
    });

    tearDownAll(() async {
      await box.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = NotificationService();
      service.attachHistoryBoxForTesting(box);
      await service.clearAll();
      await service.resetSeenStateForTesting();
      await service.setUserForTesting('user-a');
    });

    /// [minutesAgo] under 0 means "issued in the future", i.e. after the
    /// producer's cut-off, which is what makes an alert new.
    Map<String, dynamic> alert(
      String id, {
      String? state,
      String? lga,
      int minutesAgo = -1,
    }) => {
      'id': id,
      'title': 'Flood warning',
      'message': 'Water rising near the bridge.',
      'severity': 'critical',
      'createdAt': DateTime.now()
          .toUtc()
          .subtract(Duration(minutes: minutesAgo))
          .toIso8601String(),
      'target_state': ?state,
      'target_lga': ?lga,
    };

    Map<String, dynamic> report(String id, String status) => {
      'id': id,
      'status': status,
      'hazardType': 'Flooding',
    };

    test(
      'the first call only takes note; it never replays a backlog',
      () async {
        await service.recordAlerts([alert('a1'), alert('a2')]);
        expect(service.getNotifications(), isEmpty);
        await service.recordOwnReportStatuses([report('r1', 'pending')]);
        expect(service.getNotifications(), isEmpty);
      },
    );

    test('an alert targeting the user produces an entry', () async {
      await service.recordAlerts([alert('a1')]);
      await service.recordAlerts([alert('a1'), alert('a2')]);

      final entries = service.getNotifications();
      expect(entries, hasLength(1));
      expect(entries.single['title'], 'Flood warning');
      expect(entries.single['body'], 'Water rising near the bridge.');
      expect(entries.single['isRead'], isFalse);
      expect(service.unreadCount.value, 1);
      expect(notificationRouteFor(entries.single), '/alert/a2');
    });

    test('an alert already recorded is not recorded again', () async {
      await service.recordAlerts([alert('a1')]);
      await service.recordAlerts([alert('a1'), alert('a2')]);
      await service.recordAlerts([alert('a1'), alert('a2')]);
      expect(service.getNotifications(), hasLength(1));
    });

    test(
      'alerts are filtered by AlertsProvider.targetsLga before recording',
      () {
        final mine = alert('a1', state: 'Benue', lga: 'Obi');
        final theirs = alert('a2', state: 'Nasarawa', lga: 'Obi');
        expect(AlertsProvider.targetsLga(mine, 'Obi', state: 'Benue'), isTrue);
        expect(
          AlertsProvider.targetsLga(theirs, 'Obi', state: 'Benue'),
          isFalse,
        );
      },
    );

    test('a status change on the user own report produces an entry', () async {
      await service.recordOwnReportStatuses([report('r1', 'pending')]);
      await service.recordOwnReportStatuses([report('r1', 'approved')]);

      final entries = service.getNotifications();
      expect(entries, hasLength(1));
      // No stored text: the screen writes it in the current language.
      expect(entries.single['title'], '');
      expect(entries.single['body'], '');
      expect(entries.single['data']['status'], 'approved');
      expect(notificationRouteFor(entries.single), '/report/r1');
    });

    test('a peer verification outcome arrives as a status change', () async {
      await service.recordOwnReportStatuses([report('r1', 'pending')]);
      await service.recordOwnReportStatuses([report('r1', 'verified')]);
      await service.recordOwnReportStatuses([report('r2', 'pending')]);
      await service.recordOwnReportStatuses([report('r2', 'rejected')]);

      final statuses = service
          .getNotifications()
          .map((n) => n['data']['status'])
          .toSet();
      expect(statuses, {'verified', 'rejected'});
    });

    test('a newly filed report is remembered, not announced', () async {
      await service.recordOwnReportStatuses([report('r1', 'pending')]);
      await service.recordOwnReportStatuses([
        report('r1', 'pending'),
        report('r2', 'pending'),
      ]);
      expect(service.getNotifications(), isEmpty);
    });

    test('an unchanged status is not re-announced', () async {
      await service.recordOwnReportStatuses([report('r1', 'pending')]);
      await service.recordOwnReportStatuses([report('r1', 'approved')]);
      await service.recordOwnReportStatuses([report('r1', 'approved')]);
      expect(service.getNotifications(), hasLength(1));
    });
  });

  group('Push and in-app converge on one entry', () {
    late Directory dir;
    late Box<Map> box;
    late NotificationService service;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('in_app_notifs_dedup');
      Hive.init(dir.path);
      box = await Hive.openBox<Map>('notifications_history_dedup');
    });

    tearDownAll(() async {
      await box.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = NotificationService();
      service.attachHistoryBoxForTesting(box);
      await service.clearAll();
      await service.resetSeenStateForTesting();
      await service.setUserForTesting('user-a');
    });

    test('stableKeyFor identifies the event, not the delivery', () {
      expect(
        NotificationService.stableKeyFor({
          'type': 'report_status',
          'report_id': 'r1',
          'status': 'approved',
        }),
        'report_status:r1:approved',
      );
      // A push (admin_alert) and an in-app entry for the same alert agree.
      expect(
        NotificationService.stableKeyFor({
          'type': 'admin_alert',
          'alert_id': 'a1',
        }),
        NotificationService.stableKeyFor({'type': 'alert', 'id': 'a1'}),
      );
      // Two different things that happened to one report stay apart.
      expect(
        NotificationService.stableKeyFor({
          'type': 'report_status',
          'report_id': 'r1',
          'status': 'verified',
        }),
        isNot('report_status:r1:approved'),
      );
      expect(NotificationService.stableKeyFor({'type': 'chat'}), isNull);
      expect(NotificationService.stableKeyFor(null), isNull);
    });

    test('in-app first, then the push: one entry', () async {
      await service.recordOwnReportStatuses([
        {'id': 'r1', 'status': 'pending', 'hazardType': 'Flooding'},
      ]);
      await service.recordOwnReportStatuses([
        {'id': 'r1', 'status': 'approved', 'hazardType': 'Flooding'},
      ]);
      expect(service.getNotifications(), hasLength(1));

      await service.saveNotificationForTesting(
        notificationId: 'os-123',
        title: '📬 Report Update',
        body: 'Your report has been approved and an alert has been issued.',
        data: {
          'type': 'report_status',
          'report_id': 'r1',
          'status': 'approved',
        },
      );
      expect(service.getNotifications(), hasLength(1));
      expect(service.unreadCount.value, 1);
    });

    test('push first, then the in-app producer: one entry', () async {
      await service.saveNotificationForTesting(
        notificationId: 'os-456',
        title: 'Flood warning',
        body: 'Water rising near the bridge.',
        data: {'type': 'admin_alert', 'alert_id': 'a1'},
      );
      // Seed, then a "new" alert that the push already covered.
      await service.recordAlerts(const []);
      await service.recordAlerts([
        {
          'id': 'a1',
          'title': 'Flood warning',
          'message': 'Water rising.',
          'createdAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 1))
              .toIso8601String(),
        },
      ]);
      expect(service.getNotifications(), hasLength(1));
      // The push copy is kept; nothing was overwritten.
      expect(
        service.getNotifications().single['body'],
        'Water rising near the bridge.',
      );
    });

    test(
      'tapping the push marks the in-app entry read instead of copying it',
      () async {
        await service.recordAlerts(const []);
        await service.recordAlerts([
          {
            'id': 'a1',
            'title': 'Flood warning',
            'message': 'Water rising.',
            'createdAt': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 1))
                .toIso8601String(),
          },
        ]);
        expect(service.unreadCount.value, 1);

        await service.recordOpenedNotification(
          notificationId: 'os-789',
          title: 'Flood warning',
          body: 'Water rising.',
          data: {'type': 'admin_alert', 'alert_id': 'a1'},
        );
        expect(service.getNotifications(), hasLength(1));
        expect(service.unreadCount.value, 0);
      },
    );
  });

  group('In-app entries respect ownership and the cap', () {
    late Directory dir;
    late Box<Map> box;
    late NotificationService service;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('in_app_notifs_owner');
      Hive.init(dir.path);
      box = await Hive.openBox<Map>('notifications_history_owner');
    });

    tearDownAll(() async {
      await box.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = NotificationService();
      service.attachHistoryBoxForTesting(box);
      await service.clearAll();
      await service.resetSeenStateForTesting();
    });

    test('another account never sees the previous one history', () async {
      await service.setUserForTesting('user-a');
      await service.recordAlerts(const []);
      await service.recordAlerts([
        {
          'id': 'a1',
          'title': 'Flood warning',
          'message': 'Water rising.',
          'createdAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 1))
              .toIso8601String(),
        },
      ]);
      expect(service.getNotifications(), hasLength(1));

      await service.setUserForTesting('user-b');
      expect(service.getNotifications(), isEmpty);

      // The producers' memory went with it: user-b is seeded afresh and is
      // not told about user-a's alerts either.
      await service.recordAlerts([
        {
          'id': 'a1',
          'title': 'Flood warning',
          'message': 'Water rising.',
          'createdAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 1))
              .toIso8601String(),
        },
      ]);
      expect(service.getNotifications(), isEmpty);
    });

    test('signing out clears in-app entries', () async {
      await service.setUserForTesting('user-a');
      await service.recordAlerts(const []);
      await service.recordAlerts([
        {
          'id': 'a1',
          'title': 'Flood warning',
          'message': 'Water rising.',
          'createdAt': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 1))
              .toIso8601String(),
        },
      ]);
      expect(service.getNotifications(), hasLength(1));
      await service.onUserSignedOut();
      expect(service.getNotifications(), isEmpty);
    });

    test('the 200-entry cap still holds for in-app entries', () async {
      await service.setUserForTesting('user-a');
      await service.recordAlerts(const []);
      await service.recordAlerts([
        for (var i = 0; i < 210; i++)
          {
            'id': 'a$i',
            'title': 'Alert $i',
            'message': 'body',
            'createdAt': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 1))
                .toIso8601String(),
          },
      ]);
      expect(service.getNotifications().length, 200);
    });
  });

  group('History entry text', () {
    final l10n = englishL10n;

    Map<String, dynamic> entry(Map<String, dynamic> data) => {
      'id': 'x',
      'title': '',
      'body': '',
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
      'isRead': false,
    };

    test('a report-status entry is written in the current language', () {
      final e = entry({
        'type': 'report_status',
        'report_id': 'r1',
        'status': 'approved',
        'hazardType': 'Flooding',
      });
      expect(notificationTitleFor(l10n, e), l10n.notificationReportStatusTitle);
      expect(
        notificationBodyFor(l10n, e),
        l10n.notificationReportApproved(l10n.hazardFlooding),
      );
    });

    test('every produced status has a line of its own', () {
      for (final status in NotificationService.reportStatuses) {
        final body = notificationBodyFor(
          l10n,
          entry({
            'type': 'report_status',
            'report_id': 'r1',
            'status': status,
            'hazardType': 'Flooding',
          }),
        );
        expect(body, isNotEmpty, reason: status);
      }
    });

    test('an alert with no message of its own gets a localised line', () {
      expect(
        notificationBodyFor(
          l10n,
          entry({'type': 'admin_alert', 'alert_id': 'a1'}),
        ),
        l10n.notificationAlertBody,
      );
    });

    test('a push keeps the text the backend sent', () {
      final e = entry({'type': 'report_status', 'report_id': 'r1'})
        ..['title'] = '📬 Report Update'
        ..['body'] = 'Your report has been approved.';
      expect(notificationTitleFor(l10n, e), '📬 Report Update');
      expect(notificationBodyFor(l10n, e), 'Your report has been approved.');
    });

    test('an entry with no usable payload falls back to the generic title', () {
      expect(
        notificationTitleFor(l10n, entry(const {})),
        l10n.notificationsDefaultTitle,
      );
    });
  });

  group('GuideBookmarks', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      GuideBookmarks().resetForTesting();
    });

    test('a guide id falls back to the title for bundled guides', () {
      expect(GuideBookmarks.idFor({'id': 'g1', 'title': 'Flood'}), 'g1');
      expect(GuideBookmarks.idFor({'title': 'Flood'}), 'Flood');
      expect(GuideBookmarks.idFor({'id': '  '}), '');
      expect(GuideBookmarks.idFor(const {}), '');
    });

    test('toggling saves and unsaves, and survives a reload', () async {
      final bookmarks = GuideBookmarks();
      expect(await bookmarks.toggle('g1'), isTrue);
      expect(bookmarks.isBookmarked({'id': 'g1'}), isTrue);

      bookmarks.resetForTesting();
      await bookmarks.load();
      expect(bookmarks.contains('g1'), isTrue);

      expect(await bookmarks.toggle('g1'), isFalse);
      expect(bookmarks.contains('g1'), isFalse);
    });

    test('a guide with no id at all cannot be saved', () async {
      expect(await GuideBookmarks().toggle(''), isFalse);
      expect(GuideBookmarks().ids.value, isEmpty);
    });

    test('filter keeps the saved guides in order', () async {
      final bookmarks = GuideBookmarks();
      await bookmarks.toggle('g3');
      await bookmarks.toggle('g1');
      expect(
        bookmarks
            .filter([
              {'id': 'g1'},
              {'id': 'g2'},
              {'id': 'g3'},
            ])
            .map((g) => g['id']),
        ['g1', 'g3'],
      );
    });

    test('the writer and the reader share one storage key', () async {
      await GuideBookmarks().toggle('g1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(GuideBookmarks.storageKey), ['g1']);
    });
  });
}
