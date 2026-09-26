import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/session_manager.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/services/supabase_mapping.dart';
import 'package:climate_app/features/alerts/providers/alerts_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QueryPlan realtime stream planning', () {
    test('filters server-side on an immutable column only', () {
      final plan = QueryPlan.build('messages', [
        FQuery.equal('chatId', 'c1'),
        FQuery.orderDesc('sentAt'),
        FQuery.limit(50),
      ]);
      expect(plan.streamServerFilter?.column, 'chat_id');
      expect(plan.streamServerOrder?.column, 'sent_at');
      expect(plan.streamServerOrder?.ascending, isFalse);
      expect(plan.streamServerLimit, 50);
    });

    test('never filters server-side on a mutable column', () {
      final plan = QueryPlan.build('alerts', [
        FQuery.equal('isActive', true),
        FQuery.orderDesc('createdAt'),
        FQuery.limit(20),
      ]);
      expect(plan.streamServerFilter, isNull);
      // A server limit would drop rows the client-side filter keeps.
      expect(plan.streamServerLimit, isNull);
      expect(plan.streamServerOrder?.column, 'created_at');
    });

    test(
      'AlertsProvider stream is limited server-side (no is_active filter)',
      () {
        final plan = QueryPlan.build('alerts', AlertsProvider.realtimeQuery);
        expect(plan.streamServerFilter, isNull);
        expect(plan.filters, isEmpty);
        expect(plan.streamServerOrder?.column, 'created_at');
        expect(plan.streamServerOrder?.ascending, isFalse);
        expect(plan.streamServerLimit, AlertsProvider.maxAlerts * 2);
      },
    );

    test(
      'AlertsProvider drops inactive rows on the client and caps the list',
      () {
        final rows = [
          for (var i = 0; i < AlertsProvider.maxAlerts + 10; i++)
            {'id': 'a$i', 'isActive': i.isEven ? true : i % 3 != 0},
        ];
        final active = AlertsProvider.activeAlerts(rows);
        expect(active.every((a) => a['isActive'] == true), isTrue);
        expect(active.length, lessThanOrEqualTo(AlertsProvider.maxAlerts));
        expect(active.first['id'], 'a0');
        expect(
          AlertsProvider.activeAlerts([
            {'id': 'x', 'isActive': false},
            {'id': 'y', 'is_active': true},
          ]).map((a) => a['id']),
          ['y'],
        );
      },
    );

    test('prefers the immutable filter when mixed', () {
      final plan = QueryPlan.build('reports', [
        FQuery.equal('status', 'pending'),
        FQuery.equal('userId', 'u1'),
        FQuery.limit(10),
      ]);
      expect(plan.streamServerFilter?.column, 'user_id');
      expect(plan.streamServerLimit, isNull);
    });

    test('limits server-side without filters', () {
      final plan = QueryPlan.build('knowledge_base', [
        FQuery.orderDesc('updatedAt'),
        FQuery.limit(5),
      ]);
      expect(plan.streamServerFilter, isNull);
      expect(plan.streamServerLimit, 5);
    });
  });

  group('SupabaseService.imageMimeTypeForPath', () {
    test('maps known image extensions', () {
      expect(SupabaseService.imageMimeTypeForPath('/a/b.PNG'), 'image/png');
      expect(SupabaseService.imageMimeTypeForPath('x.webp'), 'image/webp');
      expect(SupabaseService.imageMimeTypeForPath('x.heic'), 'image/heic');
      expect(SupabaseService.imageMimeTypeForPath('x.jpeg'), 'image/jpeg');
      expect(SupabaseService.imageMimeTypeForPath('x.jpg'), 'image/jpeg');
    });

    test('defaults to image/jpeg, never octet-stream', () {
      expect(SupabaseService.imageMimeTypeForPath('noext'), 'image/jpeg');
      expect(SupabaseService.imageMimeTypeForPath('x.bin'), 'image/jpeg');
    });
  });

  group('SecureStorageService.clearAll', () {
    const storage = FlutterSecureStorage();

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({
        'hive_encryption_key': 'KEY',
        'auth_token': 'uid',
        'refresh_token': 'r',
        'user_role': 'ewm',
        'session_expiry': DateTime.now().toIso8601String(),
        'remember_me': 'true',
        'phone_number': '+2348000000000',
        'biometric_enabled': 'true',
        'login_attempts': '3',
      });
    });

    test('keepPreferences never deletes the Hive encryption key', () async {
      await SecureStorageService().clearAll(keepPreferences: true);

      expect(await storage.read(key: 'hive_encryption_key'), 'KEY');
      expect(await storage.read(key: 'biometric_enabled'), 'true');
      expect(await storage.read(key: 'phone_number'), isNotNull);
      expect(await storage.read(key: 'login_attempts'), '3');
      for (final k in [
        'auth_token',
        'refresh_token',
        'user_role',
        'session_expiry',
        'remember_me',
      ]) {
        expect(await storage.read(key: k), isNull, reason: k);
      }
    });

    test('full clear still keeps the Hive encryption key', () async {
      await SecureStorageService().clearAll();

      expect(await storage.read(key: 'hive_encryption_key'), 'KEY');
      expect(await storage.read(key: 'biometric_enabled'), isNull);
      expect(await storage.read(key: 'phone_number'), isNull);
      expect(await storage.read(key: 'auth_token'), isNull);
    });
  });

  group('SessionManager inactivity timeout', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));
    tearDown(() => SessionManager().cancelTimers());

    test('activity pushes a valid expiry forward', () async {
      final storage = SecureStorageService();
      final soon = DateTime.now().add(const Duration(minutes: 2));
      await storage.saveSessionExpiry(soon);

      SessionManager().recordActivity();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final expiry = await storage.getSessionExpiry();
      expect(expiry!.isAfter(soon), isTrue);
    });

    test('activity does not revive an expired session', () async {
      final storage = SecureStorageService();
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      await storage.saveSessionExpiry(past);

      SessionManager().recordActivity();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(await storage.getSessionExpiry(), past);
    });
  });
}
