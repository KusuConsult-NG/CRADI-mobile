import 'package:flutter/material.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'dart:developer' as developer;

/// Mixin that enables [FLAG_SECURE] on Android for a [StatefulWidget].
///
/// Prevents screenshots and screen recording on sensitive screens
/// (Login, Profile, Settings). On iOS the system handles this natively.
///
/// Usage:
/// ```dart
/// class _LoginScreenState extends State<LoginScreen>
///     with ScreenSecurityMixin<LoginScreen> {
///   // FLAG_SECURE is applied automatically in initState and revoked in dispose.
/// }
/// ```
mixin ScreenSecurityMixin<T extends StatefulWidget> on State<T> {
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
      await FlutterWindowManagerPlus.addFlags(
        FlutterWindowManagerPlus.FLAG_SECURE,
      );
      developer.log('FLAG_SECURE enabled', name: 'ScreenSecurityMixin');
    } on Exception catch (e) {
      // Non-fatal — app continues working without screen capture prevention.
      developer.log(
        'FLAG_SECURE enable failed: $e',
        name: 'ScreenSecurityMixin',
      );
    }
  }

  Future<void> _disableSecure() async {
    try {
      await FlutterWindowManagerPlus.clearFlags(
        FlutterWindowManagerPlus.FLAG_SECURE,
      );
    } on Exception catch (e) {
      developer.log(
        'FLAG_SECURE disable failed: $e',
        name: 'ScreenSecurityMixin',
      );
    }
  }
}
