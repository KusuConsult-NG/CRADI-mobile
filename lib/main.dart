import 'package:climate_app/core/router/app_router.dart';
import 'package:climate_app/core/theme/app_theme.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/core/providers/language_provider.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/features/chat/providers/chat_provider.dart';
import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/session_manager.dart';
import 'package:climate_app/core/services/sync_service.dart';
import 'package:climate_app/core/services/offline_queue_service.dart';
import 'package:climate_app/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'dart:developer' as developer;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Security: Initialize secure storage (singleton pattern - no need to store reference)
  SecureStorageService();

  // Security: Initialize session manager (singleton pattern - no need to store reference)
  SessionManager();

  // Initialize Hive for local data storage
  await Hive.initFlutter();

  // Initialize offline queue and sync service
  await OfflineQueueService().initialize();
  await SyncService().initialize();

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Security: Disable debug banners in release mode
  if (kReleaseMode) {
    // Disable all debug prints in production
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Initialize Crashlytics
  FlutterError.onError = (errorDetails) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    developer.log(
      'Flutter Error: ${errorDetails.exception}',
      name: 'Crashlytics',
      error: errorDetails.exception,
      stackTrace: errorDetails.stack,
    );
  };

  // Capture errors not caught by Flutter framework
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    developer.log(
      'Platform Error: $error',
      name: 'Crashlytics',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ReportingProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => ReportsStatusProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: const ClimateApp(),
    ),
  );
}

class ClimateApp extends StatelessWidget {
  const ClimateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'CRADI Mobile - Early Warning System',
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
