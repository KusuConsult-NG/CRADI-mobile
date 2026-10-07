/// The one place that resolves the backend the app runs on.
///
/// Appwrite is the only backend. The Supabase fallback has been removed.
/// Everything depends on [DataBackend] and [AuthBackend] — interfaces that
/// name capabilities, not a vendor.
library;

import 'package:climate_app/core/services/appwrite/appwrite_auth_backend.dart';
import 'package:climate_app/core/services/appwrite/appwrite_data_backend.dart';
import 'package:climate_app/core/services/appwrite/appwrite_push_targets.dart';
import 'package:climate_app/core/services/auth_backend.dart';
import 'package:climate_app/core/services/data_backend.dart';

export 'package:climate_app/core/services/auth_backend.dart';
export 'package:climate_app/core/services/data_backend.dart';

AppwriteDataBackend? _appwriteData;
AppwriteAuthBackend? _appwriteAuth;
AppwritePushTargets? _appwritePush;

AppwriteDataBackend get _awData => _appwriteData ??= AppwriteDataBackend();

/// Shares the data backend's client, so both halves use one connection and
/// one cookie jar — a second Client would hold a second session and
/// the two would disagree about who is signed in.
AppwriteAuthBackend get _awAuth =>
    _appwriteAuth ??= AppwriteAuthBackend(data: _awData);

/// Documents, realtime and files.
DataBackend get backend => _awData;

/// Sessions, sign-in and recovery.
AuthBackend get authBackend => _awAuth;

/// Registers this device for push on Appwrite, with [token] —
/// the FCM or APNs token — and subscribes it to its profile's topics.
Future<bool> registerPushTarget(String token) async =>
    (_appwritePush ??= AppwritePushTargets(data: _awData)).register(token);

/// Brings the backend up. Called once from `main()`, before `runApp`.
///
/// Awaits the session restore rather than letting it land as an event later.
/// [AuthProvider] reads `currentUser` synchronously in its constructor and
/// treats null as signed out; restoring afterwards would show every returning
/// user the login screen for a frame before correcting itself.
Future<void> initializeBackend() async {
  installBackendErrorVocabulary();
  await _awAuth.restore();
}

/// Installs the error vocabulary without connecting to anything, so the
/// pure classifiers in `backend_failure.dart` work in tests.
void installBackendErrorVocabulary() {
  AppwriteDataBackend.installErrorVocabulary();
}
