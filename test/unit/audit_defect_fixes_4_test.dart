import 'dart:io';

import 'package:climate_app/core/router/route_guard.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/services/notification_service.dart';
import 'package:climate_app/core/services/peer_verification_service.dart';
import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/supabase_mapping.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/dashboard/screens/home_screen.dart';
import 'package:climate_app/features/notifications/screens/notifications_screen.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/screens/verification_detail_screen.dart';
import 'package:climate_app/features/verification/widgets/report_staff_actions.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, StorageException;
import 'package:climate_app/core/l10n/l10n.dart';

void main() {
  // The error vocabulary is the backend's, and these tests call the pure
  // classifiers directly, with no live client to install it.
  setUpAll(SupabaseService.installErrorVocabulary);

  TestWidgetsFlutterBinding.ensureInitialized();

  group('M1 rejection reason on VerificationReport', () {
    test('fromMap reads rejectionReason and rejectedAt', () {
      final r = VerificationReport.fromMap({
        'hazardType': 'Flood',
        'status': 'rejected',
        'rejectionReason': '  Duplicate of an earlier report ',
        'rejectedAt': '2026-09-20T10:00:00Z',
      }, 'r1');
      expect(r.status, ReportStatus.rejected);
      expect(r.rejectionReason, 'Duplicate of an earlier report');
      expect(r.rejectedAt, DateTime.utc(2026, 9, 20, 10).toLocal());
      // Survives copyWith (the provider overrides display fields).
      expect(r.copyWith(title: 'x').rejectionReason, r.rejectionReason);
    });

    test('blank reason is treated as none', () {
      final r = VerificationReport.fromMap({'rejectionReason': ''}, 'r1');
      expect(r.rejectionReason, isNull);
      expect(r.rejectedAt, isNull);
    });
  });

  group('M3 dispute comments', () {
    test('a dispute without a comment is refused client-side', () async {
      final reports = ReportsStatusProvider();
      expect(
        () => reports.disputeReport('r1', comment: '   '),
        throwsA(isA<VerificationRefusedException>()),
      );
      expect(
        () => reports.disputeReport('r1'),
        throwsA(isA<VerificationRefusedException>()),
      );
    });

    test('ReportVerification reads votes with the embedded name', () {
      // Document fields, not column names: the mapping layer has already
      // turned `verifier_id` into `verifierId` by the time this runs.
      final v = ReportVerification.fromDocument({
        'verifierId': 'u1',
        'isConfirmed': false,
        'comment': ' Not flooded ',
        'submittedAt': '2026-09-20T10:00:00Z',
        'verifier': {'name': 'Ada'},
      });
      expect(v.isConfirmed, isFalse);
      expect(v.comment, 'Not flooded');
      expect(v.verifierName, 'Ada');
      expect(v.submittedAt, isNotNull);

      // Profile not readable: no name.
      final hidden = ReportVerification.fromDocument({
        'verifierId': 'u2',
        'isConfirmed': true,
        'verifier': null,
      });
      expect(hidden.verifierName, isNull);
      expect(hidden.comment, '');
    });

    test('dispute readers include staff, not plain users', () {
      expect(
        AuthProvider.verificationReaderRoles,
        containsAll([
          UserRole.ewm,
          UserRole.ldpCoordinator,
          UserRole.projectStaff,
          UserRole.techSupport,
        ]),
      );
      expect(
        AuthProvider.verificationReaderRoles,
        isNot(contains(UserRole.user)),
      );
    });
  });

  group('M2 staff actions', () {
    test('approve verified, reject pending/verified, reopen non-pending', () {
      final p = staffActionsFor(ReportStatus.pending);
      expect([p.approve, p.reject, p.reopen], [false, true, false]);
      final v = staffActionsFor(ReportStatus.verified);
      expect([v.approve, v.reject, v.reopen], [true, true, true]);
      final a = staffActionsFor(ReportStatus.approved);
      expect([a.approve, a.reject, a.reopen], [false, false, true]);
      final r = staffActionsFor(ReportStatus.rejected);
      expect([r.approve, r.reject, r.reopen], [false, false, true]);
    });
  });

  group('L9 report action errors', () {
    test('maps database refusals to readable messages', () {
      expect(
        reportActionErrorMessage(
          const PostgrestException(message: 'x', code: '22023'),
          englishL10n,
        ),
        'This report is already pending.',
      );
      expect(
        reportActionErrorMessage(
          const PostgrestException(
            message: 'You cannot reopen your own report',
            code: '42501',
          ),
          englishL10n,
        ),
        'You cannot reopen your own report',
      );
      expect(
        reportActionErrorMessage(
          const PostgrestException(
            message: 'new row violates row-level security policy',
            code: '42501',
          ),
          englishL10n,
        ),
        'You do not have permission to change this report.',
      );
      expect(
        reportActionErrorMessage(
          const DocumentNotFoundException('reports', 'r'),
          englishL10n,
        ),
        contains('permission'),
      );
      expect(
        reportActionErrorMessage(
          VerificationRefusedException((_) => 'nope'),
          englishL10n,
        ),
        'nope',
      );
    });
  });

  group('L8 IS DISTINCT FROM filter', () {
    test('matches NULL rows, unlike neq', () {
      const distinct = ColumnFilter('user_id', FilterOp.distinctFrom, 'me');
      const neq = ColumnFilter('user_id', FilterOp.neq, 'me');
      expect(distinct.matches({'user_id': null}), isTrue);
      expect(neq.matches({'user_id': null}), isFalse);
      expect(distinct.matches({'user_id': 'other'}), isTrue);
      expect(distinct.matches({'user_id': 'me'}), isFalse);
    });

    test('FQuery.distinctFrom resolves the column', () {
      final plan = QueryPlan.build('reports', [
        FQuery.distinctFrom('userId', 'me'),
      ]);
      expect(plan.filters.single.column, 'user_id');
      expect(plan.filters.single.op, FilterOp.distinctFrom);
      // Not usable as a realtime server filter.
      expect(plan.streamServerFilter, isNull);
    });
  });

  group('L3 home feed tab', () {
    test('To Verify only for verifier roles', () {
      expect(effectiveFeedTab(0, UserRole.ewm), 0);
      expect(effectiveFeedTab(0, UserRole.admin), 0);
      expect(effectiveFeedTab(0, UserRole.user), 2);
      expect(effectiveFeedTab(0, UserRole.projectStaff), 2);
      expect(effectiveFeedTab(0, null), 2);
    });

    test('Nearby falls back to My Reports for plain users', () {
      expect(effectiveFeedTab(3, UserRole.user), 2);
      expect(effectiveFeedTab(3, UserRole.ewv), 3);
      expect(effectiveFeedTab(1, UserRole.user), 1);
    });
  });

  group('L5 / storage errors', () {
    test('4xx storage errors are permanent, conflicts / limits are not', () {
      expect(
        isPermanentSyncError(
          const StorageException('too large', statusCode: '413'),
        ),
        isTrue,
      );
      expect(
        isPermanentSyncError(
          const StorageException('denied', statusCode: '403'),
        ),
        isTrue,
      );
      for (final code in ['409', '429', '408', '500', null]) {
        expect(
          isPermanentSyncError(StorageException('x', statusCode: code)),
          isFalse,
          reason: 'status $code',
        );
      }
      expect(isPermanentSyncError(ImageEncodingException()), isTrue);
    });

    test('duplicate uploads are recognised', () {
      expect(
        SupabaseService.isStorageDuplicate(
          const StorageException(
            'The resource already exists',
            statusCode: '409',
            error: 'Duplicate',
          ),
        ),
        isTrue,
      );
      expect(
        SupabaseService.isStorageDuplicate(
          const StorageException('denied', statusCode: '403'),
        ),
        isFalse,
      );
    });

    test('rate-limit refusals are recognised and do not burn retries', () {
      const e = PostgrestException(
        message: 'Too many reports submitted in the last hour.',
        code: '54000',
      );
      expect(SupabaseService.isRateLimited(e), isTrue);
      expect(isPermanentSyncError(e), isFalse);
      expect(OfflineStorageService.failureCountsAsRetry(e), isFalse);
    });
  });

  group('report field caps', () {
    test('location details are capped at 500 characters', () {
      final p = ReportingProvider()..setLocationDetails('x' * 800);
      expect(
        p.locationDetails!.length,
        ReportingProvider.maxLocationDetailsLength,
      );
    });
  });

  group('M5 biometric lock is per account', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('only the account that enabled it sees it enabled', () async {
      final storage = SecureStorageService();
      await storage.setBiometricEnabled(true, userId: 'alice');
      expect(await storage.isBiometricEnabled(forUserId: 'alice'), isTrue);
      expect(await storage.isBiometricEnabled(forUserId: 'bob'), isFalse);
    });

    test('another account signing in clears it', () async {
      final storage = SecureStorageService();
      await storage.setBiometricEnabled(true, userId: 'alice');
      await storage.bindBiometricOwner('bob');
      expect(await storage.isBiometricEnabled(), isFalse);
    });

    test('a legacy ownerless flag is bound to the signed-in user', () async {
      FlutterSecureStorage.setMockInitialValues({'biometric_enabled': 'true'});
      final storage = SecureStorageService();
      await storage.bindBiometricOwner('alice');
      expect(await storage.isBiometricEnabled(forUserId: 'alice'), isTrue);
      expect(await storage.isBiometricEnabled(forUserId: 'bob'), isFalse);
    });

    test('logout clear removes the flag', () async {
      final storage = SecureStorageService();
      await storage.setBiometricEnabled(true, userId: 'alice');
      await storage.clearAll();
      expect(await storage.isBiometricEnabled(forUserId: 'alice'), isFalse);
    });
  });

  group('L1 / M6 notification history', () {
    late Directory dir;
    late Box<Map> box;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('notif_hist_4');
      Hive.init(dir.path);
      box = await Hive.openBox<Map>('notifications_history_test_4');
      NotificationService().attachHistoryBoxForTesting(box);
    });

    tearDownAll(() async {
      await box.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    test('tapping a foreground push marks it read, no copy', () async {
      final service = NotificationService();
      await service.clearAll();
      await service.saveNotificationForTesting(
        notificationId: 'os-1',
        title: 'Report update',
        body: 'Open the app for details',
        data: {'type': 'report_status', 'report_id': 'r1'},
      );
      expect(service.unreadCount.value, 1);
      await service.recordOpenedNotification(
        notificationId: 'os-1',
        title: 'Report update',
        body: 'Open the app for details',
        data: {'type': 'report_status', 'report_id': 'r1'},
      );
      expect(service.getNotifications(), hasLength(1));
      expect(service.unreadCount.value, 0);
    });

    test('a push opened from the background is recorded once', () async {
      final service = NotificationService();
      await service.clearAll();
      await service.recordOpenedNotification(
        notificationId: 'os-2',
        title: 't',
        body: 'b',
      );
      await service.recordOpenedNotification(
        notificationId: 'os-2',
        title: 't',
        body: 'b',
      );
      expect(service.getNotifications(), hasLength(1));
      expect(service.getNotifications().single['isRead'], isTrue);
    });

    test('history items route to their target', () {
      expect(
        notificationRouteFor({
          'data': {'type': 'report_status', 'report_id': 'r9'},
        }),
        '/report/r9',
      );
      expect(
        notificationRouteFor({
          'data': <dynamic, dynamic>{'type': 'admin_alert', 'alert_id': 'a1'},
        }),
        '/alert/a1',
      );
      expect(notificationRouteFor({'data': <String, dynamic>{}}), isNull);
      expect(
        notificationRouteFor({
          'data': {'type': 'system'},
        }),
        isNull,
      );
    });
  });

  group('L7 verification detail badge', () {
    test('shows the actual status', () {
      expect(statusBadgeFor('pending', englishL10n).$1, 'PENDING VERIFICATION');
      expect(statusBadgeFor('verified', englishL10n).$1, 'VERIFIED');
      expect(statusBadgeFor('rejected', englishL10n).$1, 'REJECTED');
      expect(statusBadgeFor('approved', englishL10n).$1, 'APPROVED');
    });
  });

  group('L10 /help is reachable while pending approval', () {
    const pending = RouteGuardState(
      isInitialized: true,
      isAuthenticated: true,
      isLocked: false,
      isOffline: false,
      isVerified: true,
      isApproved: false,
      hasCompletedOnboarding: true,
    );

    test('pending user stays on /help', () {
      expect(resolveRedirect(pending, Uri.parse('/help')), isNull);
      // Other routes still go to the pending screen.
      expect(
        resolveRedirect(pending, Uri.parse('/dashboard')),
        '/pending-approval',
      );
    });
  });

  group('L2 alert broadcasting roles', () {
    test('match the alerts insert policy', () {
      expect(AuthProvider.alertManagerRoles, {
        UserRole.ewv,
        UserRole.ewr,
        UserRole.ldpCoordinator,
        UserRole.projectStaff,
        UserRole.admin,
        UserRole.techSupport,
      });
    });
  });
}
