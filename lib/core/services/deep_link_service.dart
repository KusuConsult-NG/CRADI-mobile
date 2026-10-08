import 'dart:async';
import 'dart:developer' as developer;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'package:climate_app/core/router/route_guard.dart';

/// Hosts served by the `https://cradi.ng` Universal Link / App Link filters
/// declared in `ios/Runner/Info.plist` and `android/.../AndroidManifest.xml`.
const Set<String> kAppLinkHosts = {'cradi.ng', 'www.cradi.ng'};

/// Delivers incoming `cradi://…` and `https://cradi.ng/…` links to the router.
///
/// Why an explicit listener rather than Flutter's framework deep linking
/// (`flutter_deeplinking_enabled` / `FlutterDeepLinkingEnabled`): legacy
/// Supabase auth callbacks (password recovery, email confirmation, OAuth)
/// arrive on the very same URL scheme and host, carrying paths of Supabase's
/// own (`/auth/v1/verify`, `/`, …). Framework deep linking would hand those
/// straight to go_router, which would try to navigate to them. Mapping them
/// here is what turns a dead link into an explanation — see [locationFor].
///
/// `supabase_flutter` used to consume these from its own `app_links`
/// subscription, which is why they were dropped rather than handled. That
/// package is gone, so nothing else is listening and they are ours to answer.
class DeepLinkService {
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();
  static final DeepLinkService _instance = DeepLinkService._internal();

  @visibleForTesting
  DeepLinkService.forTesting();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  bool _initialized = false;

  /// Set once the router exists. A link that arrived first (cold start) is
  /// replayed, mirroring NotificationService.
  GoRouter? _router;
  String? _pendingLocation;

  GoRouter? get router => _router;
  set router(GoRouter? value) {
    _router = value;
    final pending = _pendingLocation;
    if (value != null && pending != null) {
      _pendingLocation = null;
      value.go(pending);
    }
  }

  /// Whether [uri] is a legacy Supabase auth callback.
  ///
  /// Mirrors `supabase_flutter`'s own check (`SupabaseAuth`): the callback is
  /// identified by its parameters, in the query string or the fragment, not
  /// by its path.
  ///
  /// Appwrite's own callbacks are safe from this: magic-URL, OAuth2, email
  /// verification and recovery all come back with `userId` and `secret`, none
  /// of which is matched here. Adding a `cradi://…?code=…` link of our own
  /// would collide, though, so this list is the thing to check first if a new
  /// link ever arrives at the forgot-password screen instead of its
  /// destination.
  @visibleForTesting
  static bool isSupabaseAuthLink(Uri uri) {
    final fragmentParameters = Uri.splitQueryString(uri.fragment);
    bool has(String key) =>
        uri.queryParameters.containsKey(key) ||
        fragmentParameters.containsKey(key);
    return has('access_token') ||
        has('code') ||
        has('error') ||
        has('error_code') ||
        has('error_description');
  }

  /// The in-app location [uri] should open, or null when the link is not
  /// ours to route (a foreign host, an unknown scheme, or a bare
  /// `https://cradi.ng` with no path).
  ///
  /// Legacy Supabase auth callbacks (from the previous auth stack) are mapped
  /// to `/forgot-password?expired=1` so users clicking old reset or magic
  /// links are presented with a clear explanation instead of dropping silently.
  ///
  /// Pure: this is the whole of the link-mapping logic and is what the tests
  /// exercise.
  @visibleForTesting
  static String? locationFor(Uri uri) {
    final isCustomScheme = uri.scheme == kDeepLinkScheme;
    final isHttpHost =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        kAppLinkHosts.contains(uri.host.toLowerCase());

    if (!isCustomScheme && !isHttpHost) return null;

    if (isSupabaseAuthLink(uri)) {
      return '/forgot-password?expired=1';
    }

    if (isCustomScheme) return mapCustomSchemeLink(uri);

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // The marketing root carries no destination — leave the app where it is.
    if (segments.isEmpty) return null;
    return Uri(
      path: '/${segments.join('/')}',
      query: uri.hasQuery ? uri.query : null,
    ).toString();
  }

  /// Starts listening. Safe to call more than once.
  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    // Cold start: the launch link is delivered to the *first* subscriber of
    // the native event channel only, and `supabase_flutter` usually gets
    // there first — so it has to be read explicitly.
    Uri? initial;
    try {
      initial = await _appLinks.getInitialLink();
    } on Object catch (e) {
      developer.log('getInitialLink failed: $e', name: 'DeepLinkService');
    }
    var initialUri = initial?.toString();

    // Warm resume (and cold start when nothing subscribed before us).
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) {
        // Skip the launch link if the stream replays it to us as well.
        if (initialUri != null && uri.toString() == initialUri) {
          initialUri = null;
          return;
        }
        _handle(uri);
      },
      onError: (Object e) =>
          developer.log('Link stream error: $e', name: 'DeepLinkService'),
    );

    if (initial != null) _handle(initial);
  }

  void _handle(Uri uri) {
    final location = locationFor(uri);
    if (location == null) return;
    developer.log('Deep link $uri → $location', name: 'DeepLinkService');
    final router = _router;
    if (router == null) {
      // Cold start: the router is created a frame later; replay then.
      _pendingLocation = location;
      return;
    }
    // Safe before auth is ready: the top-level redirect parks the navigation
    // on /splash?from=<location> (or /login?from=… while locked or signed
    // out) and resumes it once the user may see it.
    router.go(location);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }
}
