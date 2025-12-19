import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

/// Service for generating unique device fingerprints for fraud detection
///
/// Creates a unique identifier based on device characteristics
/// to detect suspicious login attempts from unknown devices
class DeviceFingerprintService {
  static final DeviceFingerprintService _instance =
      DeviceFingerprintService._internal();
  factory DeviceFingerprintService() => _instance;
  DeviceFingerprintService._internal();

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Generate a unique fingerprint for the current device
  Future<String> generateFingerprint() async {
    try {
      final Map<String, dynamic> deviceData = {};

      if (kIsWeb) {
        final webInfo = await _deviceInfo.webBrowserInfo;
        deviceData['platform'] = 'web';
        deviceData['browser'] = webInfo.browserName.toString();
        deviceData['userAgent'] = webInfo.userAgent;
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceData['platform'] = 'android';
        deviceData['device'] = androidInfo.device;
        deviceData['model'] = androidInfo.model;
        deviceData['manufacturer'] = androidInfo.manufacturer;
        deviceData['androidId'] = androidInfo.id; // Unique Android ID
        deviceData['sdkInt'] = androidInfo.version.sdkInt;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceData['platform'] = 'ios';
        deviceData['name'] = iosInfo.name;
        deviceData['model'] = iosInfo.model;
        deviceData['systemVersion'] = iosInfo.systemVersion;
        deviceData['identifierForVendor'] = iosInfo.identifierForVendor;
      }

      // Add screen resolution (helps detect device)
      // Note: Would need flutter_screen_util or similar for screen size
      // For now, using basic device info only

      // Create deterministic hash of device characteristics
      final deviceString = json.encode(deviceData);
      final bytes = utf8.encode(deviceString);
      final hash = sha256.convert(bytes);

      final fingerprint = hash.toString();

      developer.log(
        'Device fingerprint generated',
        name: 'DeviceFingerprintService',
      );

      return fingerprint;
    } on Exception catch (e) {
      developer.log(
        'Error generating fingerprint: $e',
        name: 'DeviceFingerprintService',
      );
      // Fallback to timestamp-based  identifier
      return sha256.convert(utf8.encode(DateTime.now().toString())).toString();
    }
  }

  /// Get human-readable device name for display
  Future<String> getDeviceName() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return '${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return '${iosInfo.name} (${iosInfo.model})';
      } else if (kIsWeb) {
        final webInfo = await _deviceInfo.webBrowserInfo;
        return 'Web (${webInfo.browserName})';
      }
      return 'Unknown Device';
    } on Exception {
      return 'Unknown Device';
    }
  }

  /// Get device platform
  String getPlatform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}
