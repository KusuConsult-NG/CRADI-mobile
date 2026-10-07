import 'dart:math';

import 'package:appwrite/appwrite.dart' as aw;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/services/appwrite/appwrite_config.dart';
import 'package:climate_app/core/services/appwrite/appwrite_data_backend.dart';
import 'package:climate_app/core/services/appwrite/appwrite_errors.dart';
import 'package:climate_app/core/services/backend_failure.dart';

/// Registers this device for push on Appwrite, and asks the server to
/// subscribe it to the topics the profile implies.
///
/// ## Why this exists at all
///
/// Appwrite Messaging delivers to a *target* — a device token the Appwrite
/// SDK registered — and to *topics* a target is subscribed to. The server
/// half of that landed with the migration: `functions/cradi` addresses
/// `all-users`, `state-<state>` and `lga-<state>-<lga>`. Nothing ever
/// created a target, so on the Appwrite backend push reached nobody, and
/// Appwrite reports a message to an empty topic as sent.
///
/// ## The token comes from OneSignal, deliberately
///
/// Phase 3's one mitigation for the cutover is a build that registers
/// Appwrite targets *before* the switch, so tokens exist on the day —
/// OneSignal subscriptions cannot be transferred, and push reaches nobody
/// until each device has opened the new build once.
///
/// That build has to talk to both, and it already has the token: OneSignal
/// owns the FCM and APNs registration, and
/// `OneSignal.User.pushSubscription.token` is documented in the plugin as
/// "the APNS (iOS), GCM/FCM (Android) push token" — the same string
/// Appwrite wants as a target's identifier. Taking it from there is one
/// dependency and no native configuration, instead of adding
/// `firebase_messaging` beside OneSignal to obtain the token OneSignal
/// has already fetched.
///
/// When OneSignal goes, this class keeps its shape and the token comes
/// from whatever replaces it; nothing else here moves.
class AppwritePushTargets {
  AppwritePushTargets({AppwriteDataBackend? data, aw.Client? client})
    : _data = data,
      _client = client ?? data?.client ?? _defaultClient() {
    _account = aw.Account(_client);
  }

  static aw.Client _defaultClient() {
    final client = aw.Client();
    if (AppwriteConfig.endpoint.isNotEmpty) {
      client.setEndpoint(AppwriteConfig.endpoint);
    }
    if (AppwriteConfig.projectId.isNotEmpty) {
      client.setProject(AppwriteConfig.projectId);
    }
    return client;
  }

  final aw.Client _client;
  final AppwriteDataBackend? _data;
  late final aw.Account _account;

  /// SharedPreferences key holding this installation's target id.
  ///
  /// Generated once and kept, so a refreshed token updates the target it
  /// already has rather than leaving a trail of dead ones — Appwrite keeps
  /// a target whose token the provider has stopped accepting, marked
  /// `expired`, and a device that invented a new id on every launch would
  /// add one of those per launch.
  static const String targetIdKey = 'appwrite_push_target_id';

  /// The operation that subscribes this device to its profile's topics.
  static const String syncOperation = 'sync_push_subscriptions';

  /// This installation's target id, generated on first use.
  ///
  /// 20 characters of the 36 Appwrite allows, from a secure generator:
  /// the id is not a secret, but it is the name of a row in somebody
  /// else's project and a guessable one invites a collision.
  Future<String> targetId() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(targetIdKey);
    if (stored != null && stored.isNotEmpty) return stored;
    final random = Random.secure();
    final id =
        'dev-'
        '${List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join()}';
    await prefs.setString(targetIdKey, id);
    return id;
  }

  /// Which provider the token belongs to, when the project has more than one.
  ///
  /// Appwrite takes the project's *default* push provider when a target
  /// names none. A project with FCM for Android and APNs for iOS has one
  /// default and one that is not, so every device on the other platform
  /// would be filed under a provider that cannot deliver to it — accepted
  /// at registration, silent at send time. Naming it removes the guess.
  ///
  /// Empty means "the project has one provider, let it choose", which is
  /// also what an unconfigured build gets.
  String? get providerId {
    final id = defaultTargetPlatform == TargetPlatform.iOS
        ? AppConfig.pushProviderIos
        : AppConfig.pushProviderAndroid;
    return id.isEmpty ? null : id;
  }

  /// Registers [token] as this device's push target, then has the server
  /// reconcile its topic subscriptions.
  ///
  /// Both halves run on every sign-in and every token change, because
  /// both are cheap and idempotent and because that is what repairs a
  /// half-done registration: a target created in a run whose subscribe
  /// call failed is subscribed by the next one. The server answers an
  /// already-subscribed device with a 409 it counts and ignores.
  ///
  /// Throws rather than swallowing: the caller logs, and a push path that
  /// quietly does nothing is the failure this whole module is about. An
  /// empty token is not a failure — it means OneSignal has not finished
  /// registering, and its observer will call again when it has.
  Future<bool> register(String token) async {
    if (token.isEmpty) return false;
    final id = await targetId();
    try {
      await _account.createPushTarget(
        targetId: id,
        identifier: token,
        providerId: providerId,
      );
    } on aw.AppwriteException catch (e) {
      // Already registered — the usual case from the second launch on.
      if (classifyAppwriteFailure(e) != BackendFailure.duplicate) rethrow;
      await _account.updatePushTarget(targetId: id, identifier: token);
    }
    await (_data ?? AppwriteDataBackend(client: _client)).callOperation(
      syncOperation,
    );
    return true;
  }
}
