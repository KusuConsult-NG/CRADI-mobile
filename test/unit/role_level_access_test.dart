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
        hasReportTab: !techSupport,
      );

  // ── Who gets a Report tab ────────────────────────────────────────────────
  group('hasReportTabFor', () {
    test('Early Responder, Media and tech support do not', () {
      // Matrix 4.1 gives none of them Submit Reports, and the server
      // refuses the create (`NON_REPORTERS`), so a tab would only earn a
      // 403.
      expect(MainShellScreen.hasReportTabFor(UserRole.ewr), isFalse);
      expect(MainShellScreen.hasReportTabFor(UserRole.techSupport), isFalse);
      expect(MainShellScreen.hasReportTabFor(UserRole.media), isFalse);
    });

    test('every other role does', () {
      for (final role in [
        UserRole.user,
        UserRole.ewm,
        UserRole.ewv,
        UserRole.ldpCoordinator,
        UserRole.projectStaff,
        UserRole.admin,
      ]) {
        expect(MainShellScreen.hasReportTabFor(role), isTrue, reason: '$role');
      }
      // An unresolved role still gets one: the profile may not have loaded,
      // and hiding the tab from a reporter is worse than briefly offering
      // it to somebody the server will refuse.
      expect(MainShellScreen.hasReportTabFor(null), isTrue);
    });

    test('the bar is counted to match', () {
      int count({required bool admin, required bool report}) =>
          MainShellScreen.tabCountFor(showAdmin: admin, hasReportTab: report);
      expect(count(admin: false, report: true), 4); // plain user
      expect(count(admin: true, report: true), 5); // admin
      expect(count(admin: true, report: false), 4); // techSupport
      expect(count(admin: false, report: false), 3); // Early Responder
    });
  });

  // ── Tapping a tab opens the tab that was drawn there ─────────────────────
  group('routeForTab is the inverse of selectedIndexFor', () {
    test('standard bar: 2 is Report, not Settings', () {
      expect(MainShellScreen.routeForTab(2, hasReportTab: true), '/report');
      expect(MainShellScreen.routeForTab(3, hasReportTab: true), '/settings');
      expect(MainShellScreen.routeForTab(4, hasReportTab: true), '/admin');
    });

    test('techSupport bar: there is no Report tab, so 2 is Settings', () {
      expect(MainShellScreen.routeForTab(2, hasReportTab: false), '/settings');
      expect(MainShellScreen.routeForTab(3, hasReportTab: false), '/admin');
    });

    test('a tab the bar does not have opens nothing', () {
      expect(MainShellScreen.routeForTab(4, hasReportTab: false), isNull);
      expect(MainShellScreen.routeForTab(5, hasReportTab: true), isNull);
      expect(MainShellScreen.routeForTab(-1, hasReportTab: true), isNull);
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
            hasReportTab: !techSupport,
          );
          expect(route, isNotNull, reason: 'tab $i (tech=$techSupport)');
          expect(
            MainShellScreen.selectedIndexFor(
              route!,
              destinationCount: count,
              hasReportTab: !techSupport,
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

  mediaRoleTests();

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
    });

    test('ewv does not broadcast alerts, and never could', () {
      // It was in this set on the client only: `alerts.roles` in
      // functions/cradi/src/lib/policy.js has never listed it, so the
      // button was offered and the write refused.
      expect(AuthProvider.alertManagerRoles, isNot(contains(UserRole.ewv)));
    });
  });

  group('Level 3 (ewr) role sets', () {
    test('ewr judges nothing — it reads and responds', () {
      // The client's permission matrix (4.1) gives Early Responder no
      // Verify, no Validate/Reject and no Send Manual Alerts. It used to
      // have all three, which is what this now guards against.
      expect(AuthProvider.verifierRoles, isNot(contains(UserRole.ewr)));
      expect(AuthProvider.statusManagerRoles, isNot(contains(UserRole.ewr)));
      expect(AuthProvider.alertManagerRoles, isNot(contains(UserRole.ewr)));
    });

    test('the roles that do judge, per the matrix', () {
      for (final role in [UserRole.ldpCoordinator, UserRole.projectStaff]) {
        expect(AuthProvider.verifierRoles, contains(role), reason: '$role');
        expect(
          AuthProvider.statusManagerRoles,
          contains(role),
          reason: '$role',
        );
        expect(AuthProvider.alertManagerRoles, contains(role), reason: '$role');
      }
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

/// The Media role from matrix 4.1: it reads validated reports and writes
/// nothing anywhere.
///
/// Worth its own group because it is the only role in the matrix with no
/// write at all, and "no write at all" is a claim that has to be checked
/// against every set rather than assumed from the one that was added last.
void mediaRoleTests() {
  group('Media', () {
    test('is in no write set', () {
      for (final set in {
        'verifierRoles': AuthProvider.verifierRoles,
        'statusManagerRoles': AuthProvider.statusManagerRoles,
        'verificationRequestRoles': AuthProvider.verificationRequestRoles,
        'alertManagerRoles': AuthProvider.alertManagerRoles,
        'responderRoles': AuthProvider.responderRoles,
      }.entries) {
        expect(
          set.value,
          isNot(contains(UserRole.media)),
          reason: '${set.key} must not contain media',
        );
      }
    });

    test('does not read peer votes either', () {
      // Verification data is the staff deliberation on a report, not the
      // report. The matrix gives Media the validated report and nothing
      // around it.
      expect(
        AuthProvider.verificationReaderRoles,
        isNot(contains(UserRole.media)),
      );
    });

    test('stores as `media`, and parses back', () {
      // The value the report ACL names as `label:media` — via
      // accountLabels, which camel-cases the stored role. A mismatch here
      // is an ACL naming a label nobody holds, which Appwrite accepts in
      // silence and grants to nobody.
      expect(UserRole.media.dbValue, 'media');
      expect(UserRoleValue.fromDb('media'), UserRole.media);
    });

    test('its bar is Home, Alerts and Settings', () {
      expect(
        MainShellScreen.tabCountFor(showAdmin: false, hasReportTab: false),
        3,
      );
    });
  });
}
