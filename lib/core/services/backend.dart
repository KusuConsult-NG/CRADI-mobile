/// The one place that chooses which backend the app runs on.
///
/// Everything else depends on [DataBackend] and [AuthBackend] — interfaces
/// that name capabilities, not a vendor. Only this file knows there is a
/// Supabase; swapping to Appwrite is a change here and two new adapter
/// files, not a pass over the feature tree.
///
/// A plain locator rather than injection through the widget tree: these are
/// process-wide singletons used from providers, services and a handful of
/// screens alike, and most of them already reached for `SupabaseService()`
/// directly. This keeps that ergonomics and removes the vendor's name.
/// Tests that need a double construct the provider with one — every
/// provider takes its backend as a constructor argument.
library;

import 'package:climate_app/core/services/auth_backend.dart';
import 'package:climate_app/core/services/supabase_auth_backend.dart';
import 'package:climate_app/core/services/supabase_service.dart';

export 'package:climate_app/core/services/auth_backend.dart';
export 'package:climate_app/core/services/data_backend.dart';

/// Documents, realtime and files.
DataBackend get backend => SupabaseService();

/// Sessions, sign-in and recovery.
AuthBackend get authBackend => SupabaseAuthBackend();

/// Brings the backend up. Called once from `main()`; after it returns,
/// [DataBackend.isConfigured] says whether there is one.
Future<void> initializeBackend() => SupabaseService.initialize();

/// Installs the error vocabulary without connecting to anything, so the
/// pure classifiers in `backend_failure.dart` work in tests.
void installBackendErrorVocabulary() =>
    SupabaseService.installErrorVocabulary();
