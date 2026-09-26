import 'package:flutter/foundation.dart';

/// Snapshot of the app state the top-level router redirect depends on.
@immutable
class RouteGuardState {
  const RouteGuardState({
    required this.isInitialized,
    required this.isAuthenticated,
    required this.isLocked,
    required this.isOffline,
    required this.isVerified,
    required this.isApproved,
    required this.hasCompletedOnboarding,
  });

  final bool isInitialized;
  final bool isAuthenticated;
  final bool isLocked;
  final bool isOffline;
  final bool isVerified;
  final bool? isApproved;
  final bool hasCompletedOnboarding;
}

/// Routes reachable without a session.
const Set<String> kPublicRoutes = {
  '/',
  '/splash',
  '/onboarding',
  '/landing',
  '/login',
  '/register',
  '/forgot-password',
  '/reset-password',
  '/pending-approval',
  '/verify-otp',
  // Static help / contact details: reachable from the pending-approval
  // screen (and signed out).
  '/help',
  // Must be public: the offline check sends logged-out users here, and
  // redirecting them on to /login would bounce straight back to /offline.
  '/offline',
};

/// Sign-in entry points a signed-in, unlocked user has no business on.
const Set<String> kAuthEntryRoutes = {
  '/login',
  '/landing',
  '/register',
  '/onboarding',
};

/// Custom URL scheme used by shared links (`cradi://report/<id>`).
const String kDeepLinkScheme = 'cradi';

/// Whether [path] stays reachable while offline.
///
/// Public/auth routes are never swapped for the offline screen (users would
/// lose what they typed); the report wizard, knowledge base, settings and
/// contacts work from local data.
@visibleForTesting
bool isOfflineAllowed(String path) {
  if (kPublicRoutes.contains(path)) return true;
  bool under(String prefix) => path == prefix || path.startsWith('$prefix/');
  return under('/report') ||
      under('/knowledge-base') ||
      under('/settings') ||
      under('/contacts');
}

/// Validates a post-login destination carried in a `from` query parameter.
///
/// Only in-app absolute paths are accepted (no scheme, no `//host`), and
/// never an auth/public route (that would loop back to the sign-in flow).
String? sanitizeRedirectTarget(String? from) {
  if (from == null || from.isEmpty) return null;
  if (!from.startsWith('/') || from.startsWith('//')) return null;
  final uri = Uri.tryParse(from);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  final path = uri.path.isEmpty ? '/' : uri.path;
  if (kPublicRoutes.contains(path)) return null;
  return from;
}

String _withFrom(String base, String from) =>
    '$base?from=${Uri.encodeComponent(from)}';

/// Maps `cradi://<host>/<rest>` to the in-app location `/<host>/<rest>`.
/// Returns null for any other URI.
///
/// Used by [resolveRedirect] and by `DeepLinkService`, which feeds incoming
/// links to the router.
String? mapCustomSchemeLink(Uri uri) {
  if (uri.scheme != kDeepLinkScheme) return null;
  final segments = [
    if (uri.host.isNotEmpty) uri.host,
    ...uri.pathSegments.where((s) => s.isNotEmpty),
  ];
  return Uri(
    path: '/${segments.join('/')}',
    query: uri.hasQuery ? uri.query : null,
  ).toString();
}

/// One redirect step. Returns the next location, or null to stay.
String? _redirectOnce(RouteGuardState s, Uri uri) {
  final custom = mapCustomSchemeLink(uri);
  if (custom != null) return custom;

  final path = uri.path.isEmpty ? '/' : uri.path;
  // In-app location only (app links arrive as https://cradi.ng/...).
  final location = Uri(
    path: path,
    query: uri.hasQuery ? uri.query : null,
  ).toString();

  // 0. Wait for auth initialization, keeping the requested destination
  //    (cold-start notification taps / deep links) in `from`.
  if (!s.isInitialized) {
    if (path == '/splash') return null;
    if (path == '/') return '/splash';
    return _withFrom('/splash', location);
  }

  final isPublic = kPublicRoutes.contains(path);

  // 1. Biometric lock — before the offline step, so a locked user never
  //    reaches the offline screen (drafts / queued reports) or any other
  //    protected route. Everything but the non-entry public routes goes to
  //    the lock screen (/login renders it while locked). Splash is handled
  //    below (it forwards to the lock screen, keeping `from`).
  if (s.isAuthenticated && s.isLocked && path != '/' && path != '/splash') {
    if (path == '/login') return null;
    if (path == '/offline' || kAuthEntryRoutes.contains(path)) return '/login';
    if (isPublic) return null;
    final from = sanitizeRedirectTarget(location);
    return from == null ? '/login' : _withFrom('/login', from);
  }

  // 2. Offline.
  if (s.isOffline && !isOfflineAllowed(path)) return '/offline';
  if (!s.isOffline && path == '/offline') return '/dashboard';

  // 3. Leave the splash once initialized.
  if (path == '/' || path == '/splash') {
    final from = sanitizeRedirectTarget(uri.queryParameters['from']);
    if (s.isAuthenticated) {
      if (s.isLocked) {
        return from == null ? '/login' : _withFrom('/login', from);
      }
      return from ?? '/dashboard';
    }
    return s.hasCompletedOnboarding ? '/landing' : '/onboarding';
  }

  // 4. Protected routes need a session.
  if (!s.isAuthenticated) {
    if (isPublic) return null;
    final from = sanitizeRedirectTarget(location);
    return from == null ? '/login' : _withFrom('/login', from);
  }

  // 5. Signed in and unlocked: skip the sign-in screens.
  if (kAuthEntryRoutes.contains(path)) {
    return sanitizeRedirectTarget(uri.queryParameters['from']) ?? '/dashboard';
  }

  // 6. Verification.
  if (!s.isVerified && path != '/verify-access-code' && !isPublic) {
    return '/verify-access-code';
  }
  if (s.isVerified && path == '/verify-access-code') return '/dashboard';

  // 7. Approval — mirrors the database, which treats an unapproved account
  //    as having no privileges (app_role()).
  if (s.isVerified &&
      s.isApproved == false &&
      !isPublic &&
      path != '/verify-access-code') {
    return '/pending-approval';
  }
  if (s.isApproved == true && path == '/pending-approval') return '/dashboard';

  return null;
}

/// Top-level redirect for the app router.
///
/// go_router applies a top-level redirect only once per navigation, so this
/// follows its own chain (e.g. splash → from → pending-approval) until the
/// location is stable and returns the final destination (null: stay).
String? resolveRedirect(RouteGuardState state, Uri uri) {
  String? result;
  var current = uri;
  final seen = <String>{uri.toString()};
  for (var i = 0; i < 6; i++) {
    final next = _redirectOnce(state, current);
    if (next == null || !seen.add(next)) break;
    result = next;
    current = Uri.parse(next);
  }
  return result;
}
