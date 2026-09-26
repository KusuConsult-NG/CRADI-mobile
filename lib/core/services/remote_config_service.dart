import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/supabase_service.dart';

/// Server-side configurable parameters, read from the `app_settings` table
/// (key → jsonb value).
///
/// Values cascade in priority:
///   `app_settings` row > last fetched value (cached on device) > in-app
///   default.
///
/// Usage:
///   await RemoteConfigService().initialize();
///   final threshold = RemoteConfigService().minimumPeerConfirmations;
class RemoteConfigService {
  static final RemoteConfigService _instance = RemoteConfigService._internal();
  factory RemoteConfigService() => _instance;
  RemoteConfigService._internal();

  static const String _cacheKey = 'app_settings_cache';
  static const Duration _refreshInterval = Duration(hours: 1);

  // ── In-app defaults ───────────────────────────────────────────────────────
  static const Map<String, Object> _defaults = {
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

  final Map<String, Object?> _values = {};
  DateTime? _lastFetch;

  /// Load cached values, then refresh from the server in the background.
  /// Never throws.
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        final decoded = jsonDecode(cached);
        if (decoded is Map) {
          _values.addAll(decoded.map((k, v) => MapEntry(k.toString(), v)));
        }
      }
    } on Exception catch (e) {
      developer.log('app_settings cache unreadable: $e', name: 'RemoteConfig');
    }
    unawaited(refresh());
  }

  /// Fetch all settings from `app_settings` (at most once per hour unless
  /// [force] is set). Never throws.
  Future<void> refresh({bool force = false}) async {
    if (!SupabaseService.isReady) return;
    final last = _lastFetch;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _refreshInterval) {
      return;
    }
    try {
      final rows = await SupabaseService().client
          .from(AppConfig.appSettingsCollection)
          .select('key, value');
      final fresh = <String, Object?>{
        for (final row in rows) row['key'] as String: row['value'],
      };
      _values
        ..clear()
        ..addAll(fresh);
      _lastFetch = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(fresh));
      developer.log(
        'app_settings loaded: minimumPeerConfirmations='
        '$minimumPeerConfirmations maxSmsPerLgaPerDay=$maxSmsPerLgaPerDay',
        name: 'RemoteConfig',
      );
    } on Exception catch (e) {
      developer.log(
        'app_settings fetch failed (using cached/default): $e',
        name: 'RemoteConfig',
      );
    }
  }

  /// Visible for tests: replace the current values.
  void debugSetValues(Map<String, Object?> values) {
    _values
      ..clear()
      ..addAll(values);
  }

  Object? _raw(String key) => _values[key] ?? _defaults[key];

  int _getInt(String key) {
    final v = _raw(key);
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? (_defaults[key] as num).toInt();
    return (_defaults[key] as num).toInt();
  }

  double _getDouble(String key) {
    final v = _raw(key);
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v) ?? (_defaults[key] as num).toDouble();
    }
    return (_defaults[key] as num).toDouble();
  }

  bool _getBool(String key) {
    final v = _raw(key);
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    return _defaults[key] as bool;
  }

  String _getString(String key) {
    final v = _raw(key);
    return v?.toString() ?? _defaults[key] as String;
  }

  // ── Peer Verification ─────────────────────────────────────────────────────

  /// Minimum number of peer EWMs who must confirm a report before it is
  /// elevated to verified status (enforced by the database trigger; the
  /// client value is informational).
  int get minimumPeerConfirmations => _getInt('minimum_peer_confirmations');

  /// Minutes after submission before an unverified report is escalated.
  int get escalationTimeoutMinutes => _getInt('escalation_timeout_minutes');

  // ── SMS Cost Controls ─────────────────────────────────────────────────────

  int get maxSmsPerLgaPerDay => _getInt('max_sms_per_lga_per_day');
  int get maxSmsPerAlertEvent => _getInt('max_sms_per_alert_event');
  int get smsDeduplicationWindowMinutes => _getInt('sms_dedup_window_minutes');

  // ── Cache & Storage ───────────────────────────────────────────────────────

  int get contentCacheTtlHours => _getInt('content_cache_ttl_hours');
  double get maxReportImageMb => _getDouble('max_report_image_mb');

  // ── Feature Flags ─────────────────────────────────────────────────────────

  bool get featureFlagPeerChat => _getBool('feature_flag_peer_chat');
  bool get featureFlagVoiceReports => _getBool('feature_flag_voice_reports');

  // ── Force Update ─────────────────────────────────────────────────────────

  String get appMinVersion => _getString('app_min_version');
  String get appMinVersionMessage => _getString('app_min_version_message');
}
