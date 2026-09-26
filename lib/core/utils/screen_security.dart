import 'dart:developer' as developer;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Applies Android's `FLAG_SECURE` to the window while a sensitive screen is
/// mounted, which blocks screenshots, screen recording and thumbnails in the
/// recents switcher.
///
/// The flag is set through the `com.cradi.screen_security/flags` MethodChannel
/// handled in `android/app/src/main/kotlin/.../MainActivity.kt`; no
/// third-party plugin is involved.
///
/// ## Platform support
///
/// * **Android** — real protection: `FLAG_SECURE` is added on mount and
///   cleared when the last secured screen is disposed.
/// * **iOS** — **deliberate no-op.** There is no iOS equivalent of
///   `FLAG_SECURE`: UIKit cannot block the user from taking a screenshot or
///   from recording the screen, and nothing on the iOS side of this app
///   implements the usual partial mitigations (a `UITextField.isSecureTextEntry`
///   overlay, or blurring the window on `applicationWillResignActive`). The
///   mixin therefore does nothing at all on iOS rather than appearing to
///   protect the screen. If iOS coverage is needed, implement a blur overlay
///   in `AppDelegate` and extend [isSupportedPlatform].
/// * **Web / desktop** — no-op.
///
/// ## Lifecycle
///
/// Flutter builds and mounts the incoming route before disposing the outgoing
/// one, so a naive "set in initState / clear in dispose" would clear the flag
/// again when navigating from one secured screen to another. A process-wide
/// reference count ([activeCount]) makes the flag survive that hand-off: the
/// channel is only asked to clear once no secured screen remains mounted.
///
/// Usage:
/// ```dart
/// class _LoginScreenState extends State<LoginScreen>
///     with ScreenSecurityMixin<LoginScreen> {
///   // FLAG_SECURE is applied automatically in initState and released in
///   // dispose.
/// }
/// ```
mixin ScreenSecurityMixin<T extends StatefulWidget> on State<T> {
  /// MethodChannel shared by every secured screen.
  static const MethodChannel channel = MethodChannel(
    'com.cradi.screen_security/flags',
  );

  static int _activeCount = 0;

  /// Number of secured screens currently mounted. Exposed for tests.
  @visibleForTesting
  static int get activeCount => _activeCount;

  /// Resets the reference count. Tests only.
  @visibleForTesting
  static void resetForTesting() => _activeCount = 0;

  /// Whether this platform has a real screen-capture block. Android only —
  /// see the class doc for why iOS is excluded.
  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  @override
  void initState() {
    super.initState();
    acquireSecureFlag();
  }

  @override
  void dispose() {
    releaseSecureFlag();
    super.dispose();
  }

  /// Registers this screen as secured, adding `FLAG_SECURE` if it is the
  /// first one.
  @visibleForTesting
  static Future<void> acquireSecureFlag() async {
    if (!isSupportedPlatform) return;
    _activeCount++;
    if (_activeCount != 1) return;
    try {
      await channel.invokeMethod<void>('addSecureFlag');
      developer.log('FLAG_SECURE enabled', name: 'ScreenSecurityMixin');
    } on MissingPluginException {
      // Channel not registered (unit tests, unexpected embedder).
      developer.log(
        'FLAG_SECURE channel not available on this platform.',
        name: 'ScreenSecurityMixin',
      );
    } on PlatformException catch (e) {
      developer.log(
        'FLAG_SECURE enable failed: $e',
        name: 'ScreenSecurityMixin',
      );
    }
  }

  /// Unregisters this screen, clearing `FLAG_SECURE` once none remain.
  @visibleForTesting
  static Future<void> releaseSecureFlag() async {
    if (!isSupportedPlatform) return;
    if (_activeCount == 0) return;
    _activeCount--;
    if (_activeCount != 0) return;
    try {
      await channel.invokeMethod<void>('clearSecureFlag');
      developer.log('FLAG_SECURE cleared', name: 'ScreenSecurityMixin');
    } on MissingPluginException {
      // Channel not registered.
    } on PlatformException catch (e) {
      developer.log(
        'FLAG_SECURE disable failed: $e',
        name: 'ScreenSecurityMixin',
      );
    }
  }
}
