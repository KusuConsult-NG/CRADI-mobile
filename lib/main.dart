import 'dart:async';

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
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:climate_app/l10n/app_localizations.dart';
import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:climate_app/core/services/security_service.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Crash reporting is optional: only enabled when SENTRY_DSN is provided.
  // SentryFlutter.init installs FlutterError / PlatformDispatcher handlers.
  if (AppConfig.sentryDsn.isEmpty) {
    await _bootstrap();
    return;
  }
  await SentryFlutter.init((options) {
    options.dsn = AppConfig.sentryDsn;
    options.sendDefaultPii = false;
    options.tracesSampleRate = 0.0;
  }, appRunner: _bootstrap);
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Security: Enforce SSL Certificate Pinning before any network calls
  await SecurityService().initializePinning();

  // Initialize Supabase (auth session is restored from secure storage).
  try {
    await SupabaseService.initialize();
  } on Exception catch (e) {
    debugPrint('Supabase initialization failed: $e');
  }

  // Server-side settings (peer threshold, SMS caps, feature flags) from the
  // app_settings table; cached values/defaults are used until fetched.
  await RemoteConfigService().initialize();

  // Security: Initialize secure storage (singleton pattern - no need to store reference)
  SecureStorageService();

  // Security: Initialize session manager (singleton pattern - no need to store reference)
  SessionManager();

  // Initialize Hive for local data storage
  await Hive.initFlutter();

  // Initialize offline storage service for drafts and sync queue. A failure
  // (e.g. a corrupted box) must not keep the app from starting; offline
  // features degrade instead. HiveError is an Error, hence `Object`.
  try {
    await OfflineStorageService().initialize();
  } on Object catch (e, st) {
    debugPrint('Offline storage initialization failed: $e');
    ErrorHandler.logError(
      e,
      stackTrace: st,
      context: 'main.OfflineStorageService.initialize',
    );
  }

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
  AuthProvider? _auth;
  VoidCallback? _onSignedIn;

  @override
  void initState() {
    super.initState();
    // Initialize push notifications after app starts
    _initializeNotifications();
    // Wire auto-sync: when connectivity is restored, flush the offline queue
    _wireAutoSync();
    _wireDataRefresh();
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_recordActivity);
    final onSignedIn = _onSignedIn;
    if (onSignedIn != null) _auth?.removeSignInListener(onSignedIn);
    super.dispose();
  }

  /// Any interaction or navigation pushes the inactivity timeout forward.
  void _recordActivity() => _auth?.recordActivity();

  /// Refreshes data that providers loaded before it could be seen:
  /// alerts fetched before sign-in (RLS returned nothing) and zone-filtered
  /// report lists after the monitoring zone changes.
  void _wireDataRefresh() {
    _auth = context.read<AuthProvider>();
    final alerts = context.read<AlertsProvider>();
    final reports = context.read<ReportsStatusProvider>();
    _onSignedIn = () => unawaited(alerts.fetchAlerts());
    _auth!.addSignInListener(_onSignedIn!);
    context.read<ProfileProvider>().onMonitoringZoneChanged = (_) =>
        unawaited(reports.refreshReports());
  }

  void _wireAutoSync() {
    // Use addPostFrameCallback so the Provider tree is fully built before we read
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        // Single auto-sync trigger: flushes both the failed-submission queue
        // and offline drafts. ReportingProvider guards against re-entrancy.
        final reporting = context.read<ReportingProvider>();
        context.read<ConnectivityProvider>().onReconnect = () async {
          debugPrint('🔄 Auto-sync triggered by connectivity restore');
          if (!mounted) return;
          try {
            await reporting.syncPendingReports(context);
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
          // A notification that launched the app from a terminated state is
          // delivered to the OneSignal click listener and routed once the
          // router is set.
          await notificationService.initialize(
            profileProvider: profileProvider,
          );
        } on Exception catch (e) {
          debugPrint('Notification initialization error: $e');
        }
      });
    } on Exception catch (e) {
      debugPrint('Notification initialization error: $e');
      // App continues to work without notifications
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_router == null) {
      _router = createRouter(context);
      _router!.routerDelegate.addListener(_recordActivity);
    }
    // Keep NotificationService in sync if router was created after init
    NotificationService().router ??= _router;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _recordActivity(),
      child: _buildApp(),
    );
  }

  Widget _buildApp() {
    return MaterialApp.router(
      title: 'EWER Mobile - Early Warning System',
      theme: AppTheme.lightTheme,
      routerConfig: _router,
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
