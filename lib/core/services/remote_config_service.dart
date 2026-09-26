import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
    'feature_flag_peer_chat': true,
    'app_min_version': '1.0.0',
    // Empty: the app shows its own (translated) default message.
    'app_min_version_message': '',
  };

  final Map<String, Object?> _values = {};
  DateTime? _lastFetch;
  Future<void>? _inFlight;

  /// This build's version (from package_info_plus), once known.
  String? _currentVersion;

  /// True when this build is older than `app_min_version` (the app then
  /// shows a blocking "update required" screen).
  final ValueNotifier<bool> updateRequired = ValueNotifier<bool>(false);

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
    try {
      _currentVersion = (await PackageInfo.fromPlatform()).version;
    } on Exception catch (e) {
      developer.log('App version unavailable: $e', name: 'RemoteConfig');
    }
    _checkMinVersion();
    unawaited(refresh());
  }

  /// Compares dotted numeric versions ("1.0.14" vs "1.2"); a build suffix
  /// ("+22") and pre-release tags are ignored, missing parts count as 0.
  /// Returns <0, 0 or >0 like [Comparable.compareTo].
  static int compareVersions(String a, String b) {
    List<int> parts(String v) => v
        .split('+')
        .first
        .split('-')
        .first
        .trim()
        .split('.')
        .map((p) => int.tryParse(p.trim()) ?? 0)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// Whether [currentVersion] is below the configured minimum version.
  bool isBelowMinVersion(String currentVersion) {
    final min = appMinVersion.trim();
    if (min.isEmpty || currentVersion.trim().isEmpty) return false;
    return compareVersions(currentVersion, min) < 0;
  }

  void _checkMinVersion() {
    final current = _currentVersion;
    updateRequired.value = current != null && isBelowMinVersion(current);
  }

  /// Sets this build's version and re-evaluates [updateRequired] (tests).
  @visibleForTesting
  void debugSetCurrentVersion(String? version) {
    _currentVersion = version;
    _checkMinVersion();
  }

  /// Fetch all settings from `app_settings` (at most once per hour unless
  /// [force] is set). Never throws.
  Future<void> refresh({bool force = false}) {
    if (!SupabaseService.isReady) return Future<void>.value();
    final last = _lastFetch;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _refreshInterval) {
      return Future<void>.value();
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<void> _fetch() async {
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
      _checkMinVersion();
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
    _checkMinVersion();
  }

  Object? _raw(String key) => _values[key] ?? _defaults[key];

  int _getInt(String key) {
    final v = _raw(key);
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? (_defaults[key] as num).toInt();
    return (_defaults[key] as num).toInt();
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

  // ── Feature Flags ─────────────────────────────────────────────────────────

  bool get featureFlagPeerChat => _getBool('feature_flag_peer_chat');

  // ── Force Update ─────────────────────────────────────────────────────────

  String get appMinVersion => _getString('app_min_version');
  String get appMinVersionMessage => _getString('app_min_version_message');
}
