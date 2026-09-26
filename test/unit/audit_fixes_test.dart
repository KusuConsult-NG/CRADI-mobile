import 'dart:async';

import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Minimal [SupabaseService] stand-in: a signed-in user and a controllable
/// `profiles` row.
class _FakeDb implements SupabaseService {
  _FakeDb(this.user);

  sb.User? user;
  Future<Map<String, dynamic>> Function() profileRow = () async => {};

  @override
  sb.User? getCurrentUser() => user;

  @override
  String? get currentUserId => user?.id;

  @override
  Future<Map<String, dynamic>> getDocument({
    required String collectionId,
    required String documentId,
  }) => profileRow();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

sb.User _user(String id, String email) => sb.User(
  id: id,
  email: email,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'has_completed_onboarding': true});
    FlutterSecureStorage.setMockInitialValues({});
  });

  final storage = SecureStorageService();

  group('ProfileProvider', () {
    test(
      'an empty server zone means "all zones", not the cached one',
      () async {
        // Zone left on this device by the previous account.
        FlutterSecureStorage.setMockInitialValues({
          'profile_email': 'b@x.org',
          'monitoring_zone': 'Makurdi, Benue',
        });
        final db = _FakeDb(_user('u2', 'b@x.org'))
          ..profileRow = () async => {
            'name': 'B',
            'email': 'b@x.org',
            'monitoringZone': '',
          };
        final profile = ProfileProvider(supabaseService: db);
        await profile.loadProfile();

        expect(profile.monitoringZone, isNull);
        expect(await storage.read('monitoring_zone'), '');
        expect(await storage.read('profile_name'), 'B');
      },
    );

    test('a non-empty server zone is used and cached', () async {
      final db = _FakeDb(_user('u1', 'a@x.org'))
        ..profileRow = () async => {
          'name': 'A',
          'email': 'a@x.org',
          'monitoringZone': 'Benue State',
        };
      final profile = ProfileProvider(supabaseService: db);
      await profile.loadProfile();

      expect(profile.monitoringZone, 'Benue State');
      expect(await storage.read('monitoring_zone'), 'Benue State');
    });

    test(
      'a zone learned from the server notifies listeners of the change',
      () async {
        final db = _FakeDb(_user('u1', 'a@x.org'))
          ..profileRow = () async => {
            'name': 'A',
            'email': 'a@x.org',
            'monitoringZone': 'Benue State',
          };
        final profile = ProfileProvider(supabaseService: db);
        final zones = <String?>[];
        profile.onMonitoringZoneChanged = zones.add;
        await profile.loadProfile();
        expect(zones, ['Benue State']);

        // Same zone again: no redundant refetch.
        await profile.loadProfile();
        expect(zones, ['Benue State']);
      },
    );

    test('clearProfile removes the cached profile keys', () async {
      FlutterSecureStorage.setMockInitialValues({
        'profile_name': 'A',
        'profile_email': 'a@x.org',
        'profile_state': 'Benue',
        'monitoring_zone': 'Benue State',
        'biometric_enabled': 'true',
      });
      final profile = ProfileProvider(supabaseService: _FakeDb(null));
      await profile.clearProfile();

      for (final key in [
        'profile_name',
        'profile_email',
        'profile_state',
        'monitoring_zone',
      ]) {
        expect(await storage.read(key), isNull, reason: key);
      }
      // Device setting, not profile data.
      expect(await storage.read('biometric_enabled'), 'true');
    });

    test('a load that outlives a sign-out applies nothing', () async {
      final row = Completer<Map<String, dynamic>>();
      final db = _FakeDb(_user('u1', 'a@x.org'));
      final profile = ProfileProvider(supabaseService: db);
      // Let the constructor's load finish first.
      await Future<void>.delayed(Duration.zero);
      await profile.loadProfile();

      db.profileRow = () => row.future;
      final load = profile.loadProfile();
      await Future<void>.delayed(Duration.zero);
      db.user = null;
      await profile.clearProfile();
      row.complete({
        'name': 'A',
        'email': 'a@x.org',
        'monitoringZone': 'Benue State',
      });
      await load;

      // Unknown name: empty (the UI shows a localised default).
      expect(profile.name, isEmpty);
      expect(profile.monitoringZone, isNull);
      expect(profile.isLoading, isFalse);
      expect(await storage.read('profile_name'), isNull);
      expect(await storage.read('monitoring_zone'), isNull);
    });
  });

  group('Monitoring zone filter canonicalises names', () {
    Map<String, String> f(String? zone) =>
        ReportsStatusProvider.zoneFilterFor(zone);

    test('state names use the stored spelling', () {
      expect(f('benue state'), {'state': 'Benue'});
      expect(f('BENUE'), {'state': 'Benue'});
    });

    test('LGA names use the stored spelling', () {
      expect(f('makurdi, benue'), {'lga': 'Makurdi', 'state': 'Benue'});
      expect(f('MAKURDI, BENUE STATE'), {'lga': 'Makurdi', 'state': 'Benue'});
    });

    test('unknown LGA names are kept as typed', () {
      expect(f('Statehouse, benue'), {'lga': 'Statehouse', 'state': 'Benue'});
    });
  });

  group('Sync queue ownership', () {
    Map<String, dynamic> item(String? owner) => {
      'data': {'userId': ?owner},
    };

    test('signed out: only ownerless items are visible', () {
      expect(OfflineStorageService.belongsTo(item('u1'), null), isFalse);
      expect(OfflineStorageService.belongsTo(item(null), null), isTrue);
    });

    test("signed in: own and ownerless items, never another user's", () {
      expect(OfflineStorageService.belongsTo(item('u1'), 'u1'), isTrue);
      expect(OfflineStorageService.belongsTo(item(null), 'u1'), isTrue);
      expect(OfflineStorageService.belongsTo(item('u2'), 'u1'), isFalse);
    });
  });

  group('AuthProvider', () {
    test('logout notifies the sign-out listeners', () async {
      final auth = AuthProvider();
      var calls = 0;
      auth.addSignOutListener(() => calls++);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final before = calls;
      await auth.logout();
      expect(calls, greaterThan(before));
      expect(auth.isAuthenticated, isFalse);
    });
  });
}
