import 'dart:async';

import 'package:climate_app/core/services/geolocation_service.dart';
import 'package:climate_app/core/services/backend.dart';

import '../support/fake_backends.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position _pos({required DateTime at}) => Position(
  latitude: 9,
  longitude: 8,
  timestamp: at,
  accuracy: 5,
  altitude: 0,
  heading: 0,
  speed: 0,
  speedAccuracy: 0,
  altitudeAccuracy: 0,
  headingAccuracy: 0,
);

/// The signed-in account these tests run as.
const _user = AuthUser(
  id: 'u1',
  email: 'u1@example.com',
  metadata: {'name': 'Signup Name'},
);

/// Signed-in backend stub recording profile updates.
class _FakeDb implements DataBackend {
  final List<Map<String, dynamic>> updates = [];
  bool failUpdates = false;

  @override
  String? get currentUserId => _user.id;

  @override
  Future<Map<String, dynamic>> getDocument({
    required String collectionId,
    required String documentId,
  }) async => throw Exception('no backend in tests');

  @override
  Future<Map<String, dynamic>> updateDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    if (failUpdates) throw Exception('server error');
    updates.add(data);
    return data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConnectivity implements Connectivity {
  bool online = true;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    online ? ConnectivityResult.wifi : ConnectivityResult.none,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GeolocationService approximate positions', () {
    test('a fresh, recent fix is precise', () async {
      final service = GeolocationService();
      await service.fetchPositionWithFallback(
        current: () async => _pos(at: DateTime.now()),
        lastKnown: () async => null,
      );
      expect(service.lastPositionApproximate, isFalse);
    });

    test('the last-known fallback is approximate', () async {
      final service = GeolocationService();
      final p = await service.fetchPositionWithFallback(
        current: () async => throw TimeoutException('no fix'),
        lastKnown: () async => _pos(at: DateTime.now()),
      );
      expect(p, isNotNull);
      expect(service.lastPositionApproximate, isTrue);
    });

    test('a stale fix is approximate', () async {
      final service = GeolocationService();
      await service.fetchPositionWithFallback(
        current: () async =>
            _pos(at: DateTime.now().subtract(const Duration(minutes: 5))),
        lastKnown: () async => null,
      );
      expect(service.lastPositionApproximate, isTrue);
      expect(
        GeolocationService.isStaleFix(
          _pos(at: DateTime(2026, 1, 1, 12)),
          now: DateTime(2026, 1, 1, 12, 1),
        ),
        isFalse,
      );
    });
  });

  group('ProfileProvider saves', () {
    late _FakeDb db;
    late _FakeConnectivity net;
    late ProfileProvider profile;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      db = _FakeDb();
      net = _FakeConnectivity();
      profile = ProfileProvider(
        db: db,
        auth: FakeAuthBackend(_user),
        connectivity: net,
      );
      // Let the constructor's loadProfile finish.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    test('offline edits are reported and not applied', () async {
      net.online = false;
      final before = profile.name;
      final error = await profile.updateName('New Name');
      expect(error, ProfileProvider.offlineNotSavedMessage);
      expect(profile.name, before);
      expect(db.updates, isEmpty);
      expect(
        await profile.updatePhone('0800'),
        ProfileProvider.offlineNotSavedMessage,
      );
    });

    test('server errors are reported', () async {
      db.failUpdates = true;
      expect(await profile.updateName('New Name'), isNotNull);
      expect(profile.name, isNot('New Name'));
    });

    test('names are cleaned and empty names rejected', () async {
      expect(await profile.updateName('   '), isNotNull);
      expect(db.updates, isEmpty);

      expect(await profile.updateName('  Ada \u0007  Obi '), isNull);
      expect(profile.name, 'Ada Obi');
      expect(db.updates.single, {'name': 'Ada Obi'});
    });

    test(
      'monitoring zone applies locally but reports an unsaved change',
      () async {
        net.online = false;
        final error = await profile.updateMonitoringZone('Jos North');
        expect(error, ProfileProvider.offlineNotSavedMessage);
        expect(profile.monitoringZone, 'Jos North');
      },
    );
  });
}
