/// Shared setup for the tests that talk to a real Appwrite.
///
/// Three things stand between a Flutter test and a live server, and all
/// three are properties of the test harness rather than of the code:
///
/// 1. `TestWidgetsFlutterBinding` installs an `HttpOverrides` that
///    answers every request `400` without touching the network, so an
///    integration test silently exercises nothing.
/// 2. The Appwrite SDK's IO client builds a cookie jar and a user-agent
///    from `path_provider`, `device_info_plus` and `package_info_plus`,
///    none of which have an implementation in a test VM.
/// 3. `flutter_image_compress` resolves to its "unsupported" platform
///    implementation, which throws from the platform interface before
///    reaching a method channel.
///
/// These are stubbed rather than avoided, because the alternative is
/// testing a different client than the app ships.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_image_compress_platform_interface/flutter_image_compress_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

/// The endpoint the suite talks to, or empty when it is not configured.
///
/// Set at build time so the suite is skipped in CI and run deliberately:
///
///   flutter test --dart-define=APPWRITE_ENDPOINT=http://appwrite.local:8090/v1 \
///                --dart-define=APPWRITE_PROJECT_ID=cradi \
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

/// A pending report filed by **another** account, from `prep-dart.mjs`.
///
/// A reviewer may not decide their own report, so a test that files its
/// own can never reach `reopen_report` — it is refused one step earlier,
/// correctly.
const String liveForeignReport = String.fromEnvironment(
  'DART_TEST_FOREIGN_REPORT',
);

/// A session secret minted server-side by `prep-dart.mjs`.
const String liveSession = String.fromEnvironment('DART_TEST_SESSION');

/// The realtime endpoint.
///
/// Published separately in the local stack; on Cloud `/v1/realtime` is
/// proxied on the same host and the SDK derives it from the endpoint.
const String liveRealtime = String.fromEnvironment(
  'APPWRITE_REALTIME',
  defaultValue: 'ws://appwrite.local:8091/v1',
);

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
    // The upload path compresses before it uploads. `flutter_image_compress`
    // resolves to `UnsupportedFlutterImageCompress` off a real device and
    // throws `UnimplementedError` from the platform interface, before any
    // method channel is reached — so stubbing the channel does nothing.
    // The interface's `instance` is a plain static, which is the seam.
    FlutterImageCompressPlatform.instance = _PassThroughCompressor();
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

/// Hands the bytes back unchanged.
///
/// Only the two entry points the upload path uses are overridden; the
/// rest keep throwing, so a test that reaches an uncompressed path fails
/// rather than quietly passing against a stub that was never exercised.
class _PassThroughCompressor extends UnsupportedFlutterImageCompress {
  @override
  Future<Uint8List> compressWithList(
    Uint8List image, {
    int minWidth = 1920,
    int minHeight = 1080,
    int quality = 95,
    int rotate = 0,
    int inSampleSize = 1,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
  }) async => image;

  @override
  Future<Uint8List?> compressWithFile(
    String path, {
    int minWidth = 1920,
    int minHeight = 1080,
    int inSampleSize = 1,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    CompressFormat format = CompressFormat.jpeg,
    bool keepExif = false,
    int numberOfRetries = 5,
  }) async => File(path).readAsBytesSync();
}
