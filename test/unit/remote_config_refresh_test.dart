import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// app_settings are refreshed on resume (hourly), after sign-in (forced) and
/// on reconnect (unless only minutes old).
void main() {
  final t0 = DateTime(2026, 9, 26, 12);

  test('first fetch and forced refreshes always run', () {
    expect(RemoteConfigService.isRefreshDue(lastFetch: null, now: t0), isTrue);
    expect(
      RemoteConfigService.isRefreshDue(lastFetch: t0, now: t0, force: true),
      isTrue,
    );
  });

  test('the default throttle is hourly', () {
    expect(
      RemoteConfigService.isRefreshDue(
        lastFetch: t0,
        now: t0.add(const Duration(minutes: 59)),
      ),
      isFalse,
    );
    expect(
      RemoteConfigService.isRefreshDue(
        lastFetch: t0,
        now: t0.add(const Duration(hours: 1)),
      ),
      isTrue,
    );
  });

  test('a shorter max age (reconnect) refetches sooner', () {
    expect(
      RemoteConfigService.isRefreshDue(
        lastFetch: t0,
        now: t0.add(const Duration(minutes: 2)),
        maxAge: const Duration(minutes: 5),
      ),
      isFalse,
    );
    expect(
      RemoteConfigService.isRefreshDue(
        lastFetch: t0,
        now: t0.add(const Duration(minutes: 6)),
        maxAge: const Duration(minutes: 5),
      ),
      isTrue,
    );
  });

  test('the trigger helpers never throw without a backend', () async {
    final cfg = RemoteConfigService();
    await cfg.refreshOnResume();
    await cfg.refreshOnReconnect();
    await cfg.refreshOnSignIn();
  });
}
