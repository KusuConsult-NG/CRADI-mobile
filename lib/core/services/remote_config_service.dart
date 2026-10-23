import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/backend.dart';

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

  /// Minimum age of the cached values before a reconnect refetches them
  /// (connectivity can flap; a successful fetch this recent is kept).
  static const Duration _reconnectRefreshInterval = Duration(minutes: 5);

  /// How many `app_settings` rows one fetch asks for.
  ///
  /// Comfortably above the number the plan provisions, and explicit
  /// rather than left to Appwrite's silent default of 25.
  static const int _settingsPageLimit = 200;

  // ── In-app defaults ───────────────────────────────────────────────────────
  static const Map<String, Object> _defaults = {
    'minimum_peer_confirmations': 2,
    'escalation_timeout_minutes': 30,
    'max_sms_per_lga_per_day': 50,
    'max_sms_per_alert_event': 20,
    'feature_flag_peer_chat': true,
    'support_email': 'support@cradi.org',
  };

  final Map<String, Object?> _values = {};
  DateTime? _lastFetch;
  Future<void>? _inFlight;

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

  /// Whether values last fetched at [lastFetch] should be refetched at
  /// [now]: always when [force] is set or nothing was fetched yet (a failed
  /// fetch does not count), otherwise once they are [maxAge] old.
  @visibleForTesting
  static bool isRefreshDue({
    required DateTime? lastFetch,
    required DateTime now,
    bool force = false,
    Duration maxAge = _refreshInterval,
  }) {
    if (force || lastFetch == null) return true;
    return now.difference(lastFetch) >= maxAge;
  }

  /// Fetch all settings from `app_settings` (at most once per [maxAge],
  /// hourly by default, unless [force] is set). Concurrent calls share one
  /// request. Never throws.
  Future<void> refresh({
    bool force = false,
    Duration maxAge = _refreshInterval,
  }) {
    if (!backend.isConfigured) return Future<void>.value();
    if (!isRefreshDue(
      lastFetch: _lastFetch,
      now: DateTime.now(),
      force: force,
      maxAge: maxAge,
    )) {
      return Future<void>.value();
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  /// The app came back to the foreground: hourly refresh.
  Future<void> refreshOnResume() => refresh();

  /// Connectivity was restored: refetch unless the values are only a few
  /// minutes old (the previous attempt probably failed while offline).
  Future<void> refreshOnReconnect() =>
      refresh(maxAge: _reconnectRefreshInterval);

  /// A user signed in: settings are refetched for the new session.
  Future<void> refreshOnSignIn() => refresh(force: true);

  Future<void> _fetch() async {
    try {
      final rows = await backend.listDocuments(
        collectionId: AppConfig.appSettingsCollection,
        // Appwrite pages at 25 by default, silently. Every setting past
        // the 25th would simply not be in the map, and the getters fall
        // back to their defaults — so the escalation timeout or the SMS
        // cap would quietly revert with nothing in the logs. There are
        // far fewer than this today; the limit is here so that stays a
        // fact rather than an assumption.
        limitCount: _settingsPageLimit,
      );
      if (rows.length >= _settingsPageLimit) {
        // Not an error — the values that did arrive are good. But the
        // ones that did not are invisible, and this is the only place
        // that can say so.
        developer.log(
          'app_settings returned a full page of $_settingsPageLimit rows; '
          'settings beyond it are not loaded and their defaults are in use',
          name: 'RemoteConfig',
          level: 900,
        );
      }
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

  // ── Support ──────────────────────────────────────────────────────────────

  /// Address shown on the Help & Support screen (admin-managed; a blank
  /// value falls back to the in-app default).
  String get supportEmail {
    final v = _getString('support_email').trim();
    return v.isEmpty ? _defaults['support_email'] as String : v;
  }
}
