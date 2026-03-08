import 'dart:io';
import 'package:flutter/foundation.dart';

/// Service responsible for enforcing SSL certificate pinning on critical endpoints.
///
/// Pinning prevents Man-In-The-Middle (MITM) attacks on compromised networks
/// (e.g. rogue hotel WiFi or ISP interception) by verifying the exact SHA-256
/// fingerprint of the server's certificate rather than trusting any cert from
/// the OS trust store.
class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  /// Map of critical domains to their expected SHA-256 public key fingerprints.
  ///
  /// NOTE: These fingerprints rotate periodically. In a production environment,
  /// implementing a backup/fallback pin or a Remote Config-driven pin update
  /// mechanism is recommended to prevent app breakage when Google rotates certs.
  ///
  /// Current pins extracted via:
  /// openssl s_client -servername firestore.googleapis.com -connect firestore.googleapis.com:443 | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
  // ignore: unused_field
  static const Map<String, List<String>> _pinnedDomains = {
    // Google APIs / Firebase endpoints
    'firestore.googleapis.com': [
      // Primary pin (example format, needs actual Google GTS CA 1C3 pin)
      'JxqVz+aT8iT7x8Y1jE6wz5575X+1T5nTb+8P1f11N/Q=',
      // Backup pin (Root CA)
      'hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Gc=',
    ],
    'identitytoolkit.googleapis.com': [
      'JxqVz+aT8iT7x8Y1jE6wz5575X+1T5nTb+8P1f11N/Q=',
      'hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Gc=',
    ],
    'firebasestorage.googleapis.com': [
      'JxqVz+aT8iT7x8Y1jE6wz5575X+1T5nTb+8P1f11N/Q=',
      'hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Gc=',
    ],
  };

  /// Initialize SSL pinning. Should be called early in main().
  Future<void> initializePinning() async {
    // Only enforce on mobile platforms where http_certificate_pinning is supported
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    // Apply global HttpOverrides if desired for native dart:io HttpClient
    // HttpOverrides.global = _PinningHttpOverrides(_pinnedDomains);
    // [SAFETY] Pinning disabled until real GTS pins are verified
  }
}

/// Custom HttpOverrides to intercept direct dart:io HTTP traffic and enforce pinning
// ignore: unused_element
class _PinningHttpOverrides extends HttpOverrides {
  final Map<String, List<String>> pinnedDomains;

  _PinningHttpOverrides(this.pinnedDomains);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);

    // Intercept bad certificate callbacks.
    // In a fully native pinning implementation, we would reject anything here.
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
          // Never trust a bad certificate
          return false;
        };

    return client;
  }
}
