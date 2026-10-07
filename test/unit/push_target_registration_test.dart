import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:climate_app/core/services/notification_service.dart';

/// When this device registers itself as an Appwrite push target, and when
/// it does not.
///
/// The registrar itself is the backend's (`registerPushTarget`); what is
/// tested here is the decision around it, because every one of these
/// branches fails silently in production. A device that never registers
/// and a topic with nothing in it both look exactly like a quiet week.
void main() {
  _pushFlagTests();

  late List<String> registered;
  late NotificationService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    registered = [];
    service = NotificationService();
    service.pushTargetRegistrar = (token) async {
      registered.add(token);
      return true;
    };
    // It is a process-wide singleton, so the token one test registered is
    // still remembered in the next one — which would make every "it
    // registers" assertion here pass or fail depending on the order the
    // tests ran in. Signing out is what production does to forget it.
    await service.onUserSignedOut();
    await service.setUserForTesting('u1');
  });

  tearDown(() async {
    await service.setUserForTesting(null);
    service.pushTargetRegistrar = (_) async => false;
  });

  test('registers the token once the user is signed in', () async {
    await service.syncPushTarget('fcm-token-1');
    expect(registered, ['fcm-token-1']);
  });

  test('does not register the same token twice', () async {
    await service.syncPushTarget('fcm-token-1');
    await service.syncPushTarget('fcm-token-1');
    expect(registered, ['fcm-token-1']);
  });

  test('registers again when the provider reissues the token', () async {
    await service.syncPushTarget('fcm-token-1');
    await service.syncPushTarget('fcm-token-2');
    expect(registered, ['fcm-token-1', 'fcm-token-2']);
  });

  test('does nothing before there is a token', () async {
    await service.syncPushTarget(null);
    await service.syncPushTarget('');
    expect(registered, isEmpty);
  });

  test('does nothing while nobody is signed in', () async {
    await service.setUserForTesting(null);
    await service.syncPushTarget('fcm-token-1');
    expect(registered, isEmpty);
  });

  test('retries after a failure instead of recording one that threw', () async {
    var attempts = 0;
    service.pushTargetRegistrar = (token) async {
      attempts += 1;
      if (attempts == 1) throw Exception('offline');
      registered.add(token);
      return true;
    };

    // The failure must not escape: this runs on the notification path, not
    // on anything the user is waiting for.
    await service.syncPushTarget('fcm-token-1');
    expect(registered, isEmpty);

    await service.syncPushTarget('fcm-token-1');
    expect(registered, ['fcm-token-1'], reason: 'the retry was skipped');
  });

  test('retries when the backend had nothing to register', () async {
    // What the Supabase build answers, where OneSignal holds the token and
    // there is no target to create. Remembering the token as registered
    // there would skip the first real attempt after a cutover.
    service.pushTargetRegistrar = (_) async => false;
    await service.syncPushTarget('fcm-token-1');

    service.pushTargetRegistrar = (token) async {
      registered.add(token);
      return true;
    };
    await service.syncPushTarget('fcm-token-1');
    expect(registered, ['fcm-token-1']);
  });

  test(
    'forgets the token on sign-out, so the next account registers',
    () async {
      await service.syncPushTarget('device-token');
      expect(registered, ['device-token']);

      await service.onUserSignedOut();
      await service.setUserForTesting('u2');
      // The same device, the same token, a different account — and the
      // server subscribes a target to the topics of whoever owns the
      // session, so this one has to be registered again.
      await service.syncPushTarget('device-token');
      expect(registered, ['device-token', 'device-token']);
    },
  );
}

/// The two push flags, which were one.
///
/// `isPushAvailable` is "FCM came up on this build"; `hasPushPermission` is
/// "the user allows notifications". Both used to return the same field, so
/// the combination the settings screen asks about — working, but not
/// allowed — could never be true, and the localised message it guards was
/// unreachable. Asserted as the screen asks it.
void _pushFlagTests() {
  group('push availability and permission are different questions', () {
    late NotificationService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = NotificationService();
    });

    tearDown(
      () => service.setPushStateForTesting(available: false, granted: false),
    );

    test('a build with no Firebase config offers nothing to tap', () {
      service.setPushStateForTesting(available: false, granted: false);
      expect(service.isPushAvailable, isFalse);
      expect(service.hasPushPermission, isFalse);
      // Nothing for the user to fix, so the screen must not prompt.
      expect(service.isPushAvailable && !service.hasPushPermission, isFalse);
    });

    test('working FCM with a refused permission is the promptable case', () {
      service.setPushStateForTesting(available: true, granted: false);
      expect(service.isPushAvailable, isTrue);
      expect(service.hasPushPermission, isFalse);
      // This is the condition at settings_screen.dart that showed the
      // "permission needed" message. It was `x && !x` before.
      expect(service.isPushAvailable && !service.hasPushPermission, isTrue);
    });

    test('both true is the working case, and prompts nobody', () {
      service.setPushStateForTesting(available: true, granted: true);
      expect(service.isPushAvailable, isTrue);
      expect(service.hasPushPermission, isTrue);
      expect(service.isPushAvailable && !service.hasPushPermission, isFalse);
    });
  });
}
