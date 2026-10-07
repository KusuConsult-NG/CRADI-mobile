import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/session_manager.dart';
import 'package:climate_app/core/services/mapping.dart';
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
