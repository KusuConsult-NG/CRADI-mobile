import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:climate_app/core/router/app_router.dart';
import 'package:climate_app/core/theme/app_theme.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/core/providers/language_provider.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/contacts/providers/emergency_contacts_provider.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:climate_app/features/chat/providers/chat_provider.dart';
import 'package:climate_app/features/knowledge_base/providers/knowledge_provider.dart';
import 'package:climate_app/features/alerts/providers/alerts_provider.dart';
import 'package:climate_app/features/knowledge_base/providers/news_provider.dart';
import 'package:climate_app/core/services/secure_storage_service.dart';
import 'package:climate_app/core/services/session_manager.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/providers/settings_provider.dart';
import 'package:climate_app/core/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:climate_app/core/services/security_service.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('📬 Background notification: ${message.notification?.title}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Security: Enforce SSL Certificate Pinning before any network calls
  await SecurityService().initializePinning();

  // Initialize Firebase
  try {
    await Firebase.initializeApp();

    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    debugPrint('✅ FCM background handler registered');

    // Initialize Crashlytics
    // Pass all uncaught "fatal" errors from the framework to Crashlytics
    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
      // Also log to console in debug mode
      debugPrint('Flutter error: ${errorDetails.exception}');
    };

    // Pass all uncaught asynchronous errors that aren't handled by the Flutter framework to Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      debugPrint('Platform error: $error');
      return true;
    };

    debugPrint('✅ Firebase Crashlytics initialized');

    // Initialize Remote Config — fetches peer threshold, SMS caps, feature flags
    await RemoteConfigService().initialize();
  } on Exception catch (e) {
    // Firebase not configured yet - app will work without crash reporting
    debugPrint('Firebase initialization failed: $e');
  }

  // Security: Initialize secure storage (singleton pattern - no need to store reference)
  SecureStorageService();

  // Security: Initialize session manager (singleton pattern - no need to store reference)
  SessionManager();

  // Initialize Hive for local data storage
  await Hive.initFlutter();

  // Initialize offline storage service for drafts and sync queue
  await OfflineStorageService().initialize();

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize settings
  await SettingsProvider().init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ReportingProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProxyProvider<ProfileProvider, ReportsStatusProvider>(
          create: (_) => ReportsStatusProvider(),
          update: (_, profile, reports) => reports!..updateContext(profile),
        ),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => EmergencyContactsProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => KnowledgeProvider()),
        ChangeNotifierProvider(create: (_) => AlertsProvider()),
        ChangeNotifierProvider(create: (_) => NewsProvider()),
      ],
      child: const ClimateApp(),
    ),
  );
}

class ClimateApp extends StatefulWidget {
  const ClimateApp({super.key});

  @override
  State<ClimateApp> createState() => _ClimateAppState();
}

class _ClimateAppState extends State<ClimateApp> {
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    // Initialize FCM after app starts
    _initializeNotifications();
    // Wire auto-sync: when connectivity is restored, flush the offline queue
    _wireAutoSync();
  }

  void _wireAutoSync() {
    // Use addPostFrameCallback so the Provider tree is fully built before we read
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        context.read<ConnectivityProvider>().onReconnect = () async {
          debugPrint('🔄 Auto-sync triggered by connectivity restore');
          try {
            await OfflineStorageService().syncPendingReports();
          } on Exception catch (e) {
            debugPrint('Auto-sync error: $e');
          }
        };
      } on Exception catch (e) {
        debugPrint('Auto-sync wire-up error: $e');
      }
    });
  }

  Future<void> _initializeNotifications() async {
    try {
      // Use addPostFrameCallback so Provider tree is ready
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        try {
          final profileProvider = context.read<ProfileProvider>();
          final notificationService = NotificationService();
          // Inject the GoRouter so notification taps can navigate
          if (_router != null) {
            notificationService.router = _router;
          }
          await notificationService.initialize(
            profileProvider: profileProvider,
          );
          // Handle notification that launched a terminated app
          final initialMessage = await notificationService.getInitialMessage();
          if (initialMessage != null && _router != null) {
            final data = initialMessage.data;
            if (data.isNotEmpty) {
              final type = data['type'] ?? 'alert';
              final id = data['id'] ?? data['reportId'] ?? '';
              if (type == 'alert' && id.toString().isNotEmpty) {
                _router!.go('/alert/$id');
              } else if (type == 'report' && id.toString().isNotEmpty) {
                _router!.go('/report/$id');
              }
            }
          }
        } on Exception catch (e) {
          debugPrint('FCM initialization error: $e');
        }
      });
    } on Exception catch (e) {
      debugPrint('FCM initialization error: $e');
      // App continues to work without notifications
    }
  }

  @override
  Widget build(BuildContext context) {
    _router ??= createRouter(context);
    // Keep NotificationService in sync if router was created after FCM init
    NotificationService().router ??= _router;

    return MaterialApp.router(
      title: 'EWER Mobile - Early Warning System',
      theme: AppTheme.lightTheme,
      routerConfig: _router!,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
    );
  }
}
