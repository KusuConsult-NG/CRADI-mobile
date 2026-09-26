import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'has_completed_onboarding': true});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Monitoring zone filter', () {
    Map<String, String> f(String? zone) =>
        ReportsStatusProvider.zoneFilterFor(zone);

    test('no zone / all zones → no filter', () {
      expect(f(null), isEmpty);
      expect(f(''), isEmpty);
      expect(f('All Zones (No Filter)'), isEmpty);
    });

    test('"State" zone filters the state', () {
      expect(f('Benue State'), {'state': 'Benue'});
    });

    test('"LGA, State" zone filters LGA and state', () {
      expect(f('Makurdi, Benue'), {'lga': 'Makurdi', 'state': 'Benue'});
      expect(f('Makurdi, Benue State'), {'lga': 'Makurdi', 'state': 'Benue'});
    });

    test('an LGA whose name contains "state" is still an LGA zone', () {
      expect(f('Statehouse, Benue'), {'lga': 'Statehouse', 'state': 'Benue'});
    });

    test('unrecognized zone → no filter', () {
      expect(f('Benue Zone A'), isEmpty);
    });
  });

  group('Draft ownership', () {
    test('ownerless (legacy) drafts are never auto-synced', () {
      expect(OfflineStorageService.draftOwner({'id': '1'}), isNull);
      expect(
        OfflineStorageService.isAutoSyncableDraft({'id': '1'}, 'u1'),
        isFalse,
      );
    });

    test("another user's drafts are never auto-synced", () {
      expect(
        OfflineStorageService.isAutoSyncableDraft({
          'id': '1',
          'userId': 'u2',
          'status': 'draft',
        }, 'u1'),
        isFalse,
      );
    });

    test('own drafts sync unless the server refused them', () {
      expect(
        OfflineStorageService.isAutoSyncableDraft({
          'id': '1',
          'userId': 'u1',
          'status': 'draft',
        }, 'u1'),
        isTrue,
      );
      expect(
        OfflineStorageService.isAutoSyncableDraft({
          'id': '1',
          'userId': 'u1',
          'status': OfflineStorageService.statusRejected,
        }, 'u1'),
        isFalse,
      );
    });

    test('getDraftsFor is empty before storage is initialised', () {
      expect(OfflineStorageService().getDraftsFor('u1'), isEmpty);
    });
  });

  group('Sign-out cleanup', () {
    test('clearProfile does not throw when offline storage is not ready', () {
      final profile = ProfileProvider();
      expect(profile.clearProfile(), completes);
    });

    test('sign-out listeners run on a signed-out start', () async {
      final auth = AuthProvider();
      var calls = 0;
      auth.addSignOutListener(() => calls++);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(auth.isAuthenticated, isFalse);
      expect(calls, 1);
    });

    test('clearUserData drops cached lists and votes', () {
      final reports = ReportsStatusProvider();
      var notified = 0;
      reports
        ..addListener(() => notified++)
        ..clearUserData();
      expect(reports.getReports(null), isEmpty);
      expect(reports.getTotal(null), 0);
      expect(reports.hasVotedOn('r1'), isFalse);
      expect(notified, 1);
    });
  });
}
