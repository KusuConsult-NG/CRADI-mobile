/// The one place that chooses which backend the app runs on.
///
/// Everything else depends on [DataBackend] and [AuthBackend] — interfaces
/// that name capabilities, not a vendor. Only this file knows there are two
/// implementations.
///
/// A plain locator rather than injection through the widget tree: these are
/// process-wide singletons used from providers, services and a handful of
/// screens alike, and most of them already reached for a service directly.
/// Tests that need a double construct the provider with one — every
/// provider takes its backends as constructor arguments.
library;

import 'package:climate_app/core/services/appwrite/appwrite_auth_backend.dart';
import 'package:climate_app/core/services/appwrite/appwrite_config.dart';
import 'package:climate_app/core/services/appwrite/appwrite_data_backend.dart';
import 'package:climate_app/core/services/appwrite/appwrite_push_targets.dart';
import 'package:climate_app/core/services/auth_backend.dart';
import 'package:climate_app/core/services/supabase_auth_backend.dart';
import 'package:climate_app/core/services/supabase_service.dart';

export 'package:climate_app/core/services/auth_backend.dart';
export 'package:climate_app/core/services/data_backend.dart';

/// Which implementation is live.
enum BackendKind { supabase, appwrite }

/// Appwrite when it is configured, Supabase otherwise.
///
/// Chosen by which credentials the build was given rather than by a flag,
/// so there is no state in which the app is pointed at one backend and
/// talking to the other. During the migration a build carries exactly one
/// set; `env.json` decides.
BackendKind get activeBackend =>
    AppwriteConfig.isConfigured ? BackendKind.appwrite : BackendKind.supabase;

AppwriteDataBackend? _appwriteData;
AppwriteAuthBackend? _appwriteAuth;
AppwritePushTargets? _appwritePush;

AppwriteDataBackend get _awData => _appwriteData ??= AppwriteDataBackend();

/// Shares the data backend's client, so both halves use one connection and
/// one cookie jar — a second [aw.Client] would hold a second session and
/// the two would disagree about who is signed in.
AppwriteAuthBackend get _awAuth =>
    _appwriteAuth ??= AppwriteAuthBackend(data: _awData);

/// Documents, realtime and files.
DataBackend get backend => switch (activeBackend) {
  BackendKind.appwrite => _awData,
  BackendKind.supabase => SupabaseService(),
};

/// Sessions, sign-in and recovery.
AuthBackend get authBackend => switch (activeBackend) {
  BackendKind.appwrite => _awAuth,
  BackendKind.supabase => SupabaseAuthBackend(),
};

/// Registers this device for push on the active backend, with [token] —
/// the FCM or APNs token — and subscribes it to its profile's topics.
///
/// Answers `false` on the Supabase build without doing anything: there,
/// OneSignal both holds the token and decides who receives what, so there
/// is no target to register. During the cutover a build carries both, and
/// this is the half that makes the Appwrite side ready before the switch
/// (Phase 3: OneSignal subscriptions cannot be transferred, so push
/// reaches nobody until each device has opened the new build once).
///
/// Shares the data backend's client for the same reason [_awAuth] does:
/// one connection, one session.
Future<bool> registerPushTarget(String token) async => switch (activeBackend) {
  BackendKind.appwrite => (_appwritePush ??= AppwritePushTargets(
    data: _awData,
  )).register(token),
  BackendKind.supabase => false,
};

/// Brings the backend up. Called once from `main()`, before `runApp`.
///
/// The Appwrite half **awaits the session restore** rather than letting it
/// land as an event later. `AuthProvider` reads `currentUser` synchronously
/// in its constructor and treats null as signed out; restoring afterwards
/// would show every returning user the login screen for a frame before
/// correcting itself.
Future<void> initializeBackend() async {
  installBackendErrorVocabulary();
  switch (activeBackend) {
    case BackendKind.appwrite:
      await _awAuth.restore();
    case BackendKind.supabase:
      await SupabaseService.initialize();
  }
}

/// Installs the error vocabulary without connecting to anything, so the
/// pure classifiers in `backend_failure.dart` work in tests.
void installBackendErrorVocabulary() {
  switch (activeBackend) {
    case BackendKind.appwrite:
      AppwriteDataBackend.installErrorVocabulary();
    case BackendKind.supabase:
      SupabaseService.installErrorVocabulary();
  }
}
