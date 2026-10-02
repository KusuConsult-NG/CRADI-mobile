/// testing a different client than the app ships.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shared setup for the tests that talk to a real Appwrite.
///
/// Two things stand between a Flutter test and a live server, and both
/// are properties of the test harness rather than of the code:
///
/// 1. `TestWidgetsFlutterBinding` installs an `HttpOverrides` that
///    answers every request `400` without touching the network, so an
///    integration test silently exercises nothing.
/// 2. The Appwrite SDK's IO client builds a cookie jar and a user-agent
///    from `path_provider`, `device_info_plus` and `package_info_plus`,
///    none of which have an implementation in a test VM.
///
/// These are stubbed rather than avoided because the alternative is
/// The endpoint the suite talks to, or null when it is not configured.
///
/// Set at build time so the suite is skipped in CI and run deliberately:
///
///   flutter test --dart-define=APPWRITE_ENDPOINT=http://appwrite:8090/v1 \
///                --dart-define=APPWRITE_PROJECT_ID=cradi2 \
///                --dart-define=APPWRITE_DATABASE_ID=cradi \
///                test/integration
const String liveEndpoint = String.fromEnvironment('APPWRITE_ENDPOINT');
const String liveProject = String.fromEnvironment('APPWRITE_PROJECT_ID');

/// A verified account, created by `infra/appwrite/local/prep-dart.mjs`.
///
/// The tests sign in as a user rather than with an API key, because the
/// Flutter SDK has no `setKey` — an API key must never ship in an app —
/// and because signing in is what the app actually does.
const String liveEmail = String.fromEnvironment('DART_TEST_EMAIL');
const String livePassword = String.fromEnvironment('DART_TEST_PASSWORD');
const String liveUserId = String.fromEnvironment('DART_TEST_USER_ID');

/// A session secret minted server-side by `prep-dart.mjs`.
const String liveSession = String.fromEnvironment('DART_TEST_SESSION');

bool get liveConfigured =>
    liveEndpoint.isNotEmpty && liveProject.isNotEmpty && liveEmail.isNotEmpty;

/// Why the suite is skipped, or null to run it.
String? get skipUnlessLive => liveConfigured
    ? null
    : 'needs a live Appwrite: see test/integration/live_appwrite.dart';

void useLiveAppwrite() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = null;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final tempDir = Directory.systemTemp.createTempSync('appwrite-test-');

    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/device_info'),
      (call) async => <String, dynamic>{
        'name': 'test',
        'model': 'test',
        'version': '1',
        'systemName': 'linux',
        'systemVersion': '1',
        'isPhysicalDevice': false,
        'identifierForVendor': 'test',
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => <String, dynamic>{
        'appName': 'climate_app',
        'packageName': 'com.cradi.test',
        'version': '1.0.0',
        'buildNumber': '1',
      },
    );
  });
}
