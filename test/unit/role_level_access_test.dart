import 'package:flutter_test/flutter_test.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/dashboard/screens/main_shell_screen.dart';

/// Verifies that the Level 1–5 role access rules are reflected in the
/// bottom-nav tab index logic and in the role-set definitions.
void main() {
  // ── Helper ────────────────────────────────────────────────────────────────
  int tabFor(String path, {bool techSupport = false, int count = 5}) =>
      MainShellScreen.selectedIndexFor(
        path,
        destinationCount: count,
        isTechSupport: techSupport,
      );

  // ── Tapping a tab opens the tab that was drawn there ─────────────────────
  group('routeForTab is the inverse of selectedIndexFor', () {
    test('standard bar: 2 is Report, not Settings', () {
      expect(
        MainShellScreen.routeForTab(2, isTechSupport: false),
        '/report',
      );
      expect(
        MainShellScreen.routeForTab(3, isTechSupport: false),
        '/settings',
      );
      expect(MainShellScreen.routeForTab(4, isTechSupport: false), '/admin');
    });

    test('techSupport bar: there is no Report tab, so 2 is Settings', () {
      expect(MainShellScreen.routeForTab(2, isTechSupport: true), '/settings');
      expect(MainShellScreen.routeForTab(3, isTechSupport: true), '/admin');
    });

    test('a tab the bar does not have opens nothing', () {
      expect(MainShellScreen.routeForTab(4, isTechSupport: true), isNull);
      expect(MainShellScreen.routeForTab(5, isTechSupport: false), isNull);
      expect(MainShellScreen.routeForTab(-1, isTechSupport: false), isNull);
    });

    // Every tab the bar draws must round-trip: tapping tab n opens a route
    // whose own index is n again. This is what the two halves disagreeing
    // would break.
    test('every drawn tab round-trips', () {
      for (final techSupport in [false, true]) {
        final count = techSupport ? 4 : 5;
        for (var i = 0; i < count; i++) {
          final route = MainShellScreen.routeForTab(
            i,
            isTechSupport: techSupport,
          );
          expect(route, isNotNull, reason: 'tab $i (tech=$techSupport)');
          expect(
            MainShellScreen.selectedIndexFor(
              route!,
              destinationCount: count,
              isTechSupport: techSupport,
            ),
            i,
            reason: 'tab $i (tech=$techSupport) opened $route',
          );
        }
      }
    });
  });

  // ── Level 5 (techSupport) bottom nav ─────────────────────────────────────
  group('Level 5 techSupport — bottom nav has no Report tab', () {
    // techSupport bar: Home(0) Alerts(1) Settings(2) Admin(3) → 4 tabs
    const count = 4;

    test('/dashboard → 0', () {
      expect(tabFor('/dashboard', techSupport: true, count: count), 0);
    });

    test('/alerts → 1', () {
      expect(tabFor('/alerts', techSupport: true, count: count), 1);
      expect(tabFor('/alerts/detail', techSupport: true, count: count), 1);
    });

    test('/settings → 2 (not 3 like other roles)', () {
      expect(tabFor('/settings', techSupport: true, count: count), 2);
    });

    test('/admin → 3 (not 4 like admin role)', () {
      expect(tabFor('/admin', techSupport: true, count: count), 3);
      expect(tabFor('/admin/reports', techSupport: true, count: count), 3);
      expect(tabFor('/admin/knowledge', techSupport: true, count: count), 3);
    });

    test('/report → falls back to 0 (not shown in nav)', () {
      // /report is not a valid techSupport tab path — should fall back to Home.
      expect(tabFor('/report', techSupport: true, count: count), 0);
    });
  });

  // ── Level 4 (admin) bottom nav — 5 tabs including Report ─────────────────
  group('Level 4 admin — bottom nav retains Report tab', () {
    const count = 5;

    test('/report → 2 (admin can still report)', () {
      expect(tabFor('/report', techSupport: false, count: count), 2);
      expect(tabFor('/report/review', techSupport: false, count: count), 2);
    });

    test('/settings → 3', () {
      expect(tabFor('/settings', techSupport: false, count: count), 3);
    });

    test('/admin → 4', () {
      expect(tabFor('/admin', techSupport: false, count: count), 4);
      expect(tabFor('/admin/users', techSupport: false, count: count), 4);
    });
  });

  // ── Levels 1–3 bottom nav — 4 tabs, no Admin ─────────────────────────────
  group('Levels 1–3 (ewm/ewv/ewr) — 4 tabs, no Admin', () {
    const count = 4;

    test('/report → 2', () {
      expect(tabFor('/report', techSupport: false, count: count), 2);
    });

    test('/settings → 3', () {
      expect(tabFor('/settings', techSupport: false, count: count), 3);
    });

    test('/admin → falls back to 0 (not in nav)', () {
      expect(tabFor('/admin', techSupport: false, count: count), 0);
    });
  });

  // ── Role-set definitions ──────────────────────────────────────────────────
  group('Level 1 (ewm) role sets', () {
    test('ewm can cast peer-verification votes', () {
      expect(AuthProvider.verifierRoles, contains(UserRole.ewm));
    });

    test('ewm CANNOT manage report status (approve/reject)', () {
      expect(AuthProvider.statusManagerRoles, isNot(contains(UserRole.ewm)));
    });

    test('ewm CANNOT broadcast alerts', () {
      expect(AuthProvider.alertManagerRoles, isNot(contains(UserRole.ewm)));
    });
  });

  group('Level 2 (ewv) role sets', () {
    test('ewv can verify and manage status', () {
      expect(AuthProvider.verifierRoles, contains(UserRole.ewv));
      expect(AuthProvider.statusManagerRoles, contains(UserRole.ewv));
      expect(AuthProvider.verificationRequestRoles, contains(UserRole.ewv));
      expect(AuthProvider.alertManagerRoles, contains(UserRole.ewv));
    });
  });

  group('Level 3 (ewr) role sets', () {
    test('ewr has all ewv abilities', () {
      expect(AuthProvider.verifierRoles, contains(UserRole.ewr));
      expect(AuthProvider.statusManagerRoles, contains(UserRole.ewr));
      expect(AuthProvider.alertManagerRoles, contains(UserRole.ewr));
    });
  });

  group('Level 5 (techSupport) role sets', () {
    test('techSupport CANNOT report — not in verifierRoles', () {
      expect(AuthProvider.verifierRoles, isNot(contains(UserRole.techSupport)));
    });

    test('techSupport CANNOT approve/reject reports', () {
      expect(
        AuthProvider.statusManagerRoles,
        isNot(contains(UserRole.techSupport)),
      );
    });

    test('techSupport CAN broadcast alerts', () {
      expect(AuthProvider.alertManagerRoles, contains(UserRole.techSupport));
    });

    test('techSupport CAN read verification data', () {
      expect(
        AuthProvider.verificationReaderRoles,
        contains(UserRole.techSupport),
      );
    });
  });
}
