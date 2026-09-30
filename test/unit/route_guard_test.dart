import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/core/router/route_guard.dart';
import 'package:climate_app/features/dashboard/screens/main_shell_screen.dart';
import 'package:climate_app/features/verification/screens/reports_status_screen.dart';

RouteGuardState guard({
  bool initialized = true,
  bool authenticated = true,
  bool locked = false,
  bool offline = false,
  bool verified = true,
  bool? approved = true,
  bool onboarded = true,
  bool recovering = false,
}) => RouteGuardState(
  isInitialized: initialized,
  isAuthenticated: authenticated,
  isLocked: locked,
  isOffline: offline,
  isVerified: verified,
  isApproved: approved,
  hasCompletedOnboarding: onboarded,
  isPasswordRecoveryPending: recovering,
);

String? go(RouteGuardState s, String location) =>
    resolveRedirect(s, Uri.parse(location));

void main() {
  group('before auth is initialized', () {
    final s = guard(initialized: false);

    test('splash stays put', () {
      expect(go(s, '/splash'), isNull);
      expect(go(s, '/splash?from=%2Freport%2Fr1'), isNull);
    });

    test('root goes to splash without from', () {
      expect(go(s, '/'), '/splash');
    });

    test('any other destination is preserved in from', () {
      expect(go(s, '/report/r1'), '/splash?from=%2Freport%2Fr1');
      expect(
        go(s, '/reports-status?tab=approved'),
        '/splash?from=${Uri.encodeComponent('/reports-status?tab=approved')}',
      );
    });
  });

  group('resolving the splash', () {
    test('signed-in user continues to from', () {
      expect(go(guard(), '/splash?from=%2Falert%2Fa1'), '/alert/a1');
    });

    test('signed-in user without from lands on the dashboard', () {
      expect(go(guard(), '/splash'), '/dashboard');
      expect(go(guard(), '/'), '/dashboard');
    });

    test('invalid or public from values are ignored', () {
      expect(go(guard(), '/splash?from=https%3A%2F%2Fevil.com'), '/dashboard');
      expect(go(guard(), '/splash?from=%2F%2Fevil.com'), '/dashboard');
      expect(go(guard(), '/splash?from=%2Flogin'), '/dashboard');
      expect(go(guard(), '/splash?from=report'), '/dashboard');
    });

    test('locked user goes to the lock screen, keeping from', () {
      expect(
        go(guard(locked: true), '/splash?from=%2Freport%2Fr1'),
        '/login?from=%2Freport%2Fr1',
      );
      expect(go(guard(locked: true), '/splash'), '/login');
    });

    test('unverified / unapproved users are still gated', () {
      expect(
        go(guard(verified: false), '/splash?from=%2Freport%2Fr1'),
        '/verify-access-code',
      );
      expect(
        go(guard(approved: false), '/splash?from=%2Freport%2Fr1'),
        '/pending-approval',
      );
    });

    test('signed-out user goes to onboarding / landing', () {
      expect(
        go(guard(authenticated: false, onboarded: false), '/splash'),
        '/onboarding',
      );
      expect(
        go(guard(authenticated: false), '/splash?from=%2Fdashboard'),
        '/landing',
      );
    });
  });

  group('offline', () {
    final s = guard(offline: true);

    test('public / auth routes are not replaced by the offline screen', () {
      for (final r in [
        '/login',
        '/register',
        '/verify-otp',
        '/forgot-password',
        '/reset-password',
      ]) {
        expect(
          go(guard(offline: true, authenticated: false), r),
          isNull,
          reason: r,
        );
      }
    });

    test('report wizard stays available; look-alike paths do not', () {
      expect(go(s, '/report'), isNull);
      expect(go(s, '/report/details'), isNull);
      expect(go(s, '/reports-status'), '/offline');
      expect(go(s, '/report-view'), '/offline');
    });

    test('local-data sections stay available', () {
      expect(go(s, '/knowledge-base/guides'), isNull);
      expect(go(s, '/settings'), isNull);
      expect(go(s, '/contacts'), isNull);
      expect(go(s, '/dashboard'), '/offline');
    });

    test('back online leaves the offline screen', () {
      expect(go(guard(), '/offline'), '/dashboard');
      expect(
        go(guard(authenticated: false), '/offline'),
        '/login?from=%2Fdashboard',
      );
    });

    test('splash resolution while offline ends on the offline screen', () {
      expect(go(s, '/splash'), '/offline');
    });
  });

  group('locked while offline', () {
    final s = guard(locked: true, offline: true);

    test('the offline screen is never shown to a locked user', () {
      expect(go(s, '/offline'), '/login');
      expect(go(guard(locked: true), '/offline'), '/login');
    });

    test('protected routes go to the lock screen, not /offline', () {
      expect(go(s, '/dashboard'), '/login?from=%2Fdashboard');
      expect(go(s, '/reports-status'), '/login?from=%2Freports-status');
    });

    test('offline-allowed sections are locked too', () {
      expect(go(s, '/report'), '/login?from=%2Freport');
      expect(go(s, '/settings'), '/login?from=%2Fsettings');
      expect(
        go(s, '/knowledge-base/guides'),
        '/login?from=${Uri.encodeComponent('/knowledge-base/guides')}',
      );
    });

    test('splash resolves to the lock screen', () {
      expect(go(s, '/splash'), '/login');
      expect(
        go(s, '/splash?from=%2Freport%2Fr1'),
        '/login?from=%2Freport%2Fr1',
      );
    });

    test('the lock screen itself stays put', () {
      expect(go(s, '/login'), isNull);
      expect(go(s, '/register'), '/login');
    });
  });

  group('signed out', () {
    final s = guard(authenticated: false);

    test('protected routes go to login with from', () {
      expect(go(s, '/report/r1'), '/login?from=%2Freport%2Fr1');
    });

    test('public routes are allowed', () {
      expect(go(s, '/login'), isNull);
      expect(go(s, '/landing'), isNull);
      expect(go(s, '/reset-password?email=a%40b.co'), isNull);
    });
  });

  group('signed in on sign-in screens', () {
    test('unlocked users skip them', () {
      for (final r in ['/login', '/landing', '/register', '/onboarding']) {
        expect(go(guard(), r), '/dashboard', reason: r);
      }
    });

    test('login honours a valid from', () {
      expect(go(guard(), '/login?from=%2Falert%2Fa1'), '/alert/a1');
    });

    test('locked users see the lock screen', () {
      expect(go(guard(locked: true), '/login'), isNull);
      expect(go(guard(locked: true), '/landing'), '/login');
      expect(go(guard(locked: true), '/dashboard'), '/login?from=%2Fdashboard');
    });

    test('pending approval is applied after skipping login', () {
      expect(go(guard(approved: false), '/login'), '/pending-approval');
    });
  });

  group('custom scheme links', () {
    test('cradi://report/<id> maps host to the first segment', () {
      expect(mapCustomSchemeLink(Uri.parse('cradi://report/r1')), '/report/r1');
      expect(
        mapCustomSchemeLink(Uri.parse('cradi://alert/a1?x=1')),
        '/alert/a1?x=1',
      );
      expect(
        mapCustomSchemeLink(Uri.parse('https://cradi.ng/report/r1')),
        isNull,
      );
    });

    test('redirect resolves them', () {
      expect(go(guard(), 'cradi://report/r1'), '/report/r1');
      expect(
        go(guard(initialized: false), 'cradi://alert/a1'),
        '/splash?from=%2Falert%2Fa1',
      );
    });
  });

  group('sanitizeRedirectTarget', () {
    test('accepts in-app protected paths', () {
      expect(sanitizeRedirectTarget('/report/r1'), '/report/r1');
      expect(
        sanitizeRedirectTarget('/reports-status?tab=pending'),
        '/reports-status?tab=pending',
      );
    });

    test('rejects everything else', () {
      for (final v in [
        null,
        '',
        'report/r1',
        '//evil.com/x',
        'https://evil.com',
        '/login',
        '/splash',
        '/offline',
        '/',
      ]) {
        expect(sanitizeRedirectTarget(v), isNull, reason: '$v');
      }
    });
  });

  group('MainShellScreen.selectedIndexFor', () {
    test('maps tabs', () {
      expect(
        MainShellScreen.selectedIndexFor('/dashboard', destinationCount: 5),
        0,
      );
      expect(
        MainShellScreen.selectedIndexFor('/alerts/detail', destinationCount: 4),
        1,
      );
      expect(
        MainShellScreen.selectedIndexFor('/report/review', destinationCount: 4),
        2,
      );
      expect(
        MainShellScreen.selectedIndexFor('/settings', destinationCount: 4),
        3,
      );
      expect(
        MainShellScreen.selectedIndexFor('/admin/users', destinationCount: 5),
        4,
      );
    });

    test('never returns an index outside the rendered bar', () {
      expect(
        MainShellScreen.selectedIndexFor('/admin', destinationCount: 4),
        0,
      );
      expect(
        MainShellScreen.selectedIndexFor('/my-reports', destinationCount: 4),
        0,
      );
    });
  });

  group('ReportsStatusScreen.tabIndexFor', () {
    test('maps tab names and defaults to pending', () {
      expect(ReportsStatusScreen.tabIndexFor('pending'), 0);
      expect(ReportsStatusScreen.tabIndexFor('verified'), 1);
      expect(ReportsStatusScreen.tabIndexFor('Approved'), 2);
      expect(ReportsStatusScreen.tabIndexFor('rejected'), 3);
      expect(ReportsStatusScreen.tabIndexFor(null), 0);
      expect(ReportsStatusScreen.tabIndexFor('bogus'), 0);
    });
  });

  // A recovery link used to be built from the project's Site URL, which is the
  // admin panel — app users who tapped it landed on a staff login screen. The
  // link now opens the app, and these pin what happens once it has.
  group('an open recovery session', () {
    test('parks the app on the reset screen, whatever was asked for', () {
      final s = guard(recovering: true);
      expect(go(s, '/dashboard'), kPasswordRecoveryLocation);
      expect(go(s, '/login'), kPasswordRecoveryLocation);
      expect(go(s, '/settings'), kPasswordRecoveryLocation);
    });

    test('beats the biometric lock — the user is here because they are shut out', () {
      final s = guard(recovering: true, locked: true);
      expect(go(s, '/dashboard'), kPasswordRecoveryLocation);
      expect(go(s, '/login'), kPasswordRecoveryLocation);
    });

    test('beats the offline screen, and an unapproved account still gets in', () {
      expect(go(guard(recovering: true, offline: true), '/dashboard'),
          kPasswordRecoveryLocation);
      expect(go(guard(recovering: true, approved: false, verified: false), '/dashboard'),
          kPasswordRecoveryLocation);
    });

    test('the reset screen itself is left alone, so there is no loop', () {
      final s = guard(recovering: true);
      expect(go(s, kPasswordRecoveryLocation), isNull);
      expect(go(s, '/reset-password'), isNull);
    });

    test('waits for initialization rather than pre-empting it', () {
      // The flag cannot be trusted before the provider has read its session.
      expect(go(guard(initialized: false, recovering: true), '/dashboard'),
          startsWith('/splash'));
    });

    test('with no recovery pending nothing changes', () {
      expect(go(guard(), '/dashboard'), isNull);
    });
  });

  // The link in the mail has to point at the app, and at a route that exists.
  test('the recovery redirect is a deep link the app claims', () {
    expect(kPasswordResetRedirect, startsWith('$kDeepLinkScheme://'));
    expect(mapCustomSchemeLink(Uri.parse(kPasswordResetRedirect)),
        '/reset-password');
    expect(kPublicRoutes, contains('/reset-password'));
  });
}
