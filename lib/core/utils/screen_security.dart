import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:developer' as developer;

/// Mixin that enables [FLAG_SECURE] on Android for a [StatefulWidget].
///
/// Prevents screenshots and screen recording on sensitive screens
/// (Login, Profile, Settings). Implemented via a native MethodChannel
/// in MainActivity — no third-party plugin required.
///
/// On iOS the system handles screen capture prevention natively.
///
/// Usage:
/// ```dart
/// class _LoginScreenState extends State<LoginScreen>
///     with ScreenSecurityMixin<LoginScreen> {
///   // FLAG_SECURE is applied automatically in initState and revoked in dispose.
/// }
/// ```
mixin ScreenSecurityMixin<T extends StatefulWidget> on State<T> {
  static const MethodChannel _channel = MethodChannel(
    'com.cradi.screen_security/flags',
  );

  @override
  void initState() {
    super.initState();
    _enableSecure();
  }

  @override
  void dispose() {
    _disableSecure();
    super.dispose();
  }

  Future<void> _enableSecure() async {
    try {
      await _channel.invokeMethod<void>('addSecureFlag');
      developer.log('FLAG_SECURE enabled', name: 'ScreenSecurityMixin');
    } on MissingPluginException {
      // Non-fatal on iOS / web where the channel is not registered.
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

  Future<void> _disableSecure() async {
    try {
      await _channel.invokeMethod<void>('clearSecureFlag');
    } on MissingPluginException {
      // Non-fatal on iOS / web.
    } on PlatformException catch (e) {
      developer.log(
        'FLAG_SECURE disable failed: $e',
        name: 'ScreenSecurityMixin',
      );
    }
  }
}
