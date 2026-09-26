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

  /// Map of critical domains to their expected SHA-256 SPKI fingerprints.
  ///
  /// Empty: pinning is not enforced. To enable it, add the Supabase project
  /// host (`<ref>.supabase.co`) and the Railway backend host with a current
  /// and a backup pin, e.g. extracted via:
  /// openssl s_client -servername HOST -connect HOST:443 | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
  // ignore: unused_field
  static const Map<String, List<String>> _pinnedDomains = {};

  /// Initialize SSL pinning. Should be called early in main().
  Future<void> initializePinning() async {
    // Only enforce on mobile platforms.
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
