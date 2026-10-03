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
