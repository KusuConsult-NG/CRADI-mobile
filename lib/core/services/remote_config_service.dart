import 'dart:developer' as developer;
import 'package:firebase_remote_config/firebase_remote_config.dart';

/// Wrapper around Firebase Remote Config that provides typed accessors
/// for all server-side configurable parameters.
///
/// Values cascade in priority:
///   Remote Config server value > in-app defaults > compile-time fallback.
///
/// Fetch interval in production: 12 hours (Firebase minimum for free tier).
/// In debug: 0 seconds (instant fetch, uses debug quota).
///
/// Usage:
///   await RemoteConfigService().initialize();
///   final threshold = RemoteConfigService().minimumPeerConfirmations;
class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  RemoteConfigService._internal();

  FirebaseRemoteConfig get _rc => FirebaseRemoteConfig.instance;

  // ── In-app defaults ───────────────────────────────────────────────────────
  // These match the previous compile-time constants so the app behaves
  // correctly before the first successful fetch.
  static const Map<String, dynamic> _defaults = {
    'minimum_peer_confirmations': 2,
    'escalation_timeout_minutes': 30,
    'max_sms_per_lga_per_day': 50,
    'max_sms_per_alert_event': 20,
    'sms_dedup_window_minutes': 60,
    'content_cache_ttl_hours': 24,
    'max_report_image_mb': 5,
    'feature_flag_peer_chat': true,
    'feature_flag_voice_reports': false,
    'app_min_version': '1.0.0',
    'app_min_version_message': 'Please update the EWER app to continue.',
  };

  /// Initialize Remote Config. Call once from [main()] after Firebase.initializeApp().
  Future<void> initialize() async {
    try {
      await _rc.setDefaults(_defaults);

      await _rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 15),
          // Production: 12h; Debug: 0 (instant, uses debug quota)
          minimumFetchInterval: const Duration(hours: 12),
        ),
      );

      // Activate cached values immediately, then fetch fresh values in background
      await _rc.activate();
      _rc
          .fetchAndActivate()
          .then((_) {
            developer.log(
              'RemoteConfig: background fetch + activate complete',
              name: 'RemoteConfigService',
            );
          })
          .catchError((Object e) {
            developer.log(
              'RemoteConfig: background fetch failed (using cached/default): $e',
              name: 'RemoteConfigService',
            );
          });

      developer.log(
        'RemoteConfigService initialized. '
        'minimumPeerConfirmations=$minimumPeerConfirmations '
        'maxSmsPerLgaPerDay=$maxSmsPerLgaPerDay',
        name: 'RemoteConfigService',
      );
    } on Exception catch (e) {
      // Non-fatal: app continues with in-app defaults
      developer.log(
        'RemoteConfigService: init failed, using defaults: $e',
        name: 'RemoteConfigService',
      );
    }
  }

  // ── Peer Verification ─────────────────────────────────────────────────────

  /// Minimum number of peer EWMs who must confirm a report before it is
  /// elevated to validated status. Previously a compile-time constant (= 2).
  /// Now server-configurable — can be raised to 3 without a Play Store update.
  int get minimumPeerConfirmations => _rc.getInt('minimum_peer_confirmations');

  /// How many minutes after report submission before an unverified report
  /// is auto-escalated to the LDP coordinator.
  int get escalationTimeoutMinutes => _rc.getInt('escalation_timeout_minutes');

  // ── SMS Cost Controls ─────────────────────────────────────────────────────

  /// Maximum SMS messages that can be sent to recipients in a single LGA
  /// in a 24-hour rolling window. Prevents coordinated false-alert drains.
  int get maxSmsPerLgaPerDay => _rc.getInt('max_sms_per_lga_per_day');

  /// Maximum SMS recipients for a single alert event, regardless of LGA cap.
  int get maxSmsPerAlertEvent => _rc.getInt('max_sms_per_alert_event');

  /// Deduplication window in minutes. If the same alert fires SMS to the
  /// same LGA twice within this window, the second send is suppressed.
  int get smsDeduplicationWindowMinutes =>
      _rc.getInt('sms_dedup_window_minutes');

  // ── Cache & Storage ───────────────────────────────────────────────────────

  int get contentCacheTtlHours => _rc.getInt('content_cache_ttl_hours');

  double get maxReportImageMb => _rc.getDouble('max_report_image_mb');

  // ── Feature Flags ─────────────────────────────────────────────────────────

  bool get featureFlagPeerChat => _rc.getBool('feature_flag_peer_chat');
  bool get featureFlagVoiceReports => _rc.getBool('feature_flag_voice_reports');

  // ── Force Update ─────────────────────────────────────────────────────────

  String get appMinVersion => _rc.getString('app_min_version');
  String get appMinVersionMessage => _rc.getString('app_min_version_message');
}
