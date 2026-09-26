import 'package:climate_app/core/router/route_guard.dart';
import 'package:climate_app/core/services/deep_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

String? loc(String url) => DeepLinkService.locationFor(Uri.parse(url));

bool auth(String url) => DeepLinkService.isSupabaseAuthLink(Uri.parse(url));

void main() {
  group('custom scheme links', () {
    test('map host + path to an in-app location', () {
      expect(loc('cradi://report/r1'), '/report/r1');
      expect(loc('cradi://alert/a1'), '/alert/a1');
      expect(loc('cradi://reports-status'), '/reports-status');
    });

    test('keep the query string', () {
      expect(
        loc('cradi://reports-status?tab=approved'),
        '/reports-status?tab=approved',
      );
    });

    test('a scheme-only link resolves to the root', () {
      expect(loc('cradi://'), '/');
    });

    test('another app\'s scheme is ignored', () {
      expect(loc('other://report/r1'), isNull);
      expect(loc('ng.cradi.app://report/r1'), isNull);
    });
  });

  group('https app links', () {
    test('cradi.ng paths map to in-app locations', () {
      expect(loc('https://cradi.ng/report/r1'), '/report/r1');
      expect(loc('https://www.cradi.ng/alert/a1'), '/alert/a1');
      expect(loc('https://CRADI.NG/report/r1'), '/report/r1');
    });

    test('query strings survive and empty segments are dropped', () {
      expect(
        loc('https://cradi.ng/reports-status/?tab=approved'),
        '/reports-status?tab=approved',
      );
    });

    test('the bare marketing root does not navigate', () {
      expect(loc('https://cradi.ng'), isNull);
      expect(loc('https://cradi.ng/'), isNull);
    });

    test('other hosts are ignored', () {
      expect(loc('https://evil.com/report/r1'), isNull);
      expect(loc('https://cradi.ng.evil.com/report/r1'), isNull);
      expect(loc('https://notcradi.ng/report/r1'), isNull);
    });
  });

  group('Supabase auth callbacks are left to supabase_flutter', () {
    test('recognised by query parameters', () {
      expect(auth('https://cradi.ng/welcome?code=abc123'), isTrue);
      expect(auth('https://cradi.ng/x?error=access_denied'), isTrue);
      expect(auth('https://cradi.ng/x?error_code=otp_expired'), isTrue);
      expect(auth('https://cradi.ng/x?error_description=Email+link'), isTrue);
    });

    test('recognised by fragment parameters', () {
      expect(
        auth('cradi://login-callback/#access_token=t&refresh_token=r'),
        isTrue,
      );
      expect(auth('https://cradi.ng/#access_token=t&type=recovery'), isTrue);
    });

    test('share links are not auth callbacks', () {
      expect(auth('cradi://report/r1'), isFalse);
      expect(auth('https://cradi.ng/alert/a1'), isFalse);
    });

    test('are never routed, whatever path they carry', () {
      expect(loc('cradi://login-callback/#access_token=t'), isNull);
      expect(loc('cradi://report/r1?code=abc'), isNull);
      expect(loc('https://cradi.ng/reset-password?code=abc'), isNull);
      expect(loc('https://cradi.ng/#access_token=t&type=recovery'), isNull);
    });
  });

  group('the mapped location survives the router guard', () {
    RouteGuardState guard({
      bool initialized = true,
      bool authenticated = true,
      bool locked = false,
    }) => RouteGuardState(
      isInitialized: initialized,
      isAuthenticated: authenticated,
      isLocked: locked,
      isOffline: false,
      isVerified: true,
      isApproved: true,
      hasCompletedOnboarding: true,
    );

    test('warm resume: a signed-in user lands on the report', () {
      final location = loc('cradi://report/r1')!;
      expect(resolveRedirect(guard(), Uri.parse(location)), isNull);
    });

    test('cold start: the destination is parked on the splash', () {
      final location = loc('https://cradi.ng/report/r1')!;
      expect(
        resolveRedirect(guard(initialized: false), Uri.parse(location)),
        '/splash?from=%2Freport%2Fr1',
      );
      // …and is resumed once auth has initialized.
      expect(
        resolveRedirect(guard(), Uri.parse('/splash?from=%2Freport%2Fr1')),
        '/report/r1',
      );
    });

    test('a locked user is sent to the lock screen keeping the target', () {
      final location = loc('cradi://alert/a1')!;
      expect(
        resolveRedirect(guard(locked: true), Uri.parse(location)),
        '/login?from=%2Falert%2Fa1',
      );
    });

    test('a signed-out user is sent to sign in keeping the target', () {
      final location = loc('cradi://report/r1')!;
      expect(
        resolveRedirect(guard(authenticated: false), Uri.parse(location)),
        '/login?from=%2Freport%2Fr1',
      );
    });
  });
}
