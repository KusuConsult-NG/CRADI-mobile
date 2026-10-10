import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:climate_app/features/auth/widgets/sign_out_notice_listener.dart';
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
import 'package:climate_app/core/services/appwrite/appwrite_config.dart';
import 'package:climate_app/core/services/session_manager.dart';
import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/providers/settings_provider.dart';
import 'package:climate_app/core/services/notification_service.dart';
import 'package:climate_app/core/services/deep_link_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/l10n/fallback_localizations.dart';
import 'package:climate_app/core/widgets/force_update_gate.dart';
import 'package:climate_app/core/services/remote_config_service.dart';
import 'package:climate_app/core/services/backend.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// Top-level FCM background message handler (required by firebase_messaging).
/// Runs in a separate isolate — keep it minimal.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // History is written by the foreground handler; background messages are
  // displayed by the OS automatically. Nothing to do here.
}

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

  // Firebase must be initialized before any firebase_messaging calls.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } on Exception catch (e) {
    debugPrint('Firebase initialization failed (push disabled): $e');
  }

  // Initialize the backend. Appwrite is the only one; an unconfigured
  // build gets the Unconfigured* backends and behaves as signed out.
  try {
    await initializeBackend();
  } on Exception catch (e) {
    debugPrint('Backend initialization failed: $e');
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

  // A build with no backend compiled in has to say so.
  //
  // `AppwriteConfig.endpoint` and `projectId` are bare
  // `String.fromEnvironment` with no default, so a build missing
  // `--dart-define-from-file=env.json` compiles in empty strings and
  // `isConfigured` is false for the life of the binary. Every backend call
  // then fails, and the app's own handling of that is to behave as signed
  // out (`AuthProvider`, `auth_provider.dart`) — which is indistinguishable
  // from a broken server. An APK built this way was diagnosed as a mail
  // outage on 9 October 2026 before anyone thought to check the build.
  //
  // CI already refuses to produce a *tagged release* this way
  // (`.github/workflows/ci.yml`, "this build would start signed out"). This
  // is the same guard for a build made by hand, where nothing else checks.
  if (!AppwriteConfig.isConfigured) {
    runApp(const _UnconfiguredApp());
    return;
  }

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

class _ClimateAppState extends State<ClimateApp> with WidgetsBindingObserver {
  GoRouter? _router;
  AuthProvider? _auth;
  VoidCallback? _onSignedIn;
  VoidCallback? _onSignedOut;

  /// In-app producers for the notifications history: the screen must show
  /// what happened to this user even when push is not configured, was
  /// denied, or has not delivered (yet). See NotificationService's
  /// "In-app producers" section.
  AlertsProvider? _alerts;
  ProfileProvider? _profile;
  VoidCallback? _onAlertsChanged;
  StreamSubscription<List<Map<String, dynamic>>>? _ownReportsSub;

  @override
  void initState() {
    super.initState();
    // Server-side settings (app_min_version, feature flags) are refreshed
    // when the app returns to the foreground, not only at startup.
    WidgetsBinding.instance.addObserver(this);
    // Initialize push notifications after app starts
    _initializeNotifications();
    // Start listening for cradi:// and https://cradi.ng links. Supabase auth
    // callbacks are filtered out by DeepLinkService and stay with
    // supabase_flutter's own listener.
    unawaited(DeepLinkService().initialize());
    // Wire auto-sync: when connectivity is restored, flush the offline queue
    _wireAutoSync();
    _wireDataRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router?.routerDelegate.removeListener(_recordActivity);
    final onSignedIn = _onSignedIn;
    if (onSignedIn != null) _auth?.removeSignInListener(onSignedIn);
    final onSignedOut = _onSignedOut;
    if (onSignedOut != null) _auth?.removeSignOutListener(onSignedOut);
    final onAlertsChanged = _onAlertsChanged;
    if (onAlertsChanged != null) {
      _alerts?.removeListener(onAlertsChanged);
      _profile?.removeListener(onAlertsChanged);
    }
    unawaited(_ownReportsSub?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(RemoteConfigService().refreshOnResume());
    }
  }

  /// Any interaction or navigation pushes the inactivity timeout forward.
  void _recordActivity() => _auth?.recordActivity();

  /// Refreshes data that providers loaded before it could be seen:
  /// alerts, profile and report lists fetched before sign-in (RLS returned
  /// nothing, or they belong to the previous account on a shared device),
  /// and zone-filtered report lists after the monitoring zone changes.
  /// On sign-out the previous user's cached lists, votes and profile are
  /// dropped.
  void _wireDataRefresh() {
    _auth = context.read<AuthProvider>();
    final alerts = context.read<AlertsProvider>();
    final reports = context.read<ReportsStatusProvider>();
    final profile = context.read<ProfileProvider>();
    // Zone-filtered lists need the new user's monitoring zone first.
    // clearUserData() also dropped the user's own (userId-scoped) lists, so
    // those are reloaded too; screens showing them refetch on their own.
    Future<void> reloadFor(String uid) async {
      await profile.loadProfile();
      // Signed out (or another account signed in) meanwhile: that event
      // clears / reloads the lists itself.
      if (_auth?.currentUser?.id != uid) return;
      await Future.wait([
        reports.refreshReports(),
        reports.refreshReports(userId: uid),
      ]);
    }

    _onSignedIn = () {
      final uid = _auth?.currentUser?.id;
      reports.clearUserData();
      unawaited(RemoteConfigService().refreshOnSignIn());
      unawaited(alerts.fetchAlerts());
      if (uid != null) unawaited(reloadFor(uid));
      _watchOwnReports(profile);
    };
    _onSignedOut = () {
      // The alerts feed is per session (RLS); restarted by fetchAlerts.
      alerts.stopRealtime();
      reports.clearUserData();
      unawaited(profile.clearProfile());
      unawaited(_ownReportsSub?.cancel());
      _ownReportsSub = null;
    };
    _auth!
      ..addSignInListener(_onSignedIn!)
      ..addSignOutListener(_onSignedOut!);
    profile.onMonitoringZoneChanged = (_) =>
        unawaited(reports.refreshReports());
    // Reports uploaded by an offline sync appear in the lists right away
    // (staff lists and the user's own list).
    context.read<ReportingProvider>().onReportsSynced = () {
      final uid = _auth?.currentUser?.id;
      unawaited(reports.refreshReports());
      if (uid != null) unawaited(reports.refreshReports(userId: uid));
    };

    // Producer 1: an alert that targets this user. AlertsProvider notifies
    // on every realtime update; the service ignores alerts it has already
    // recorded, so calling it on each notification is harmless.
    _alerts = alerts;
    _profile = profile;
    _onAlertsChanged = () {
      if (_auth?.currentUser == null || profile.isLoading) return;
      unawaited(
        NotificationService().recordAlerts(
          alerts.alertsForLga(profile.lga, state: profile.state),
        ),
      );
    };
    alerts.addListener(_onAlertsChanged!);
    // Which alerts target the user also changes when their profile (LGA,
    // state) arrives or changes, not only when the alerts list does.
    profile.addListener(_onAlertsChanged!);
    if (_auth?.currentUser != null) _watchOwnReports(profile);
  }

  /// Producer 2: a change to the status of one of the user's own reports
  /// (which is also how a peer verification outcome reaches its author).
  void _watchOwnReports(ProfileProvider profile) {
    unawaited(_ownReportsSub?.cancel());
    _ownReportsSub = profile.getUserReportsStream().listen(
      (rows) => unawaited(NotificationService().recordOwnReportStatuses(rows)),
      onError: (Object e) =>
          ErrorHandler.logError(e, context: 'ownReports.notifications'),
    );
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
          unawaited(RemoteConfigService().refreshOnReconnect());
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
          final notificationService = NotificationService();
          // Inject the GoRouter so notification taps can navigate
          if (_router != null) {
            notificationService.router = _router;
          }
          // A notification that launched the app from a terminated state is
          // delivered to FCM's `getInitialMessage` and routed once the router
          // is set.
          await notificationService.initialize();
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
    // Same for deep links: a link that launched the app (cold start) is
    // replayed the moment the router exists.
    DeepLinkService().router ??= _router;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _recordActivity(),
      child: _buildApp(),
    );
  }

  Widget _buildApp() {
    // The in-app language choice drives the locale; Flutter has no
    // Material/Cupertino translations for Hausa, so fallback delegates
    // supply English ones instead of null.
    return Consumer<LanguageProvider>(
      builder: (context, language, _) => MaterialApp.router(
        onGenerateTitle: (context) => context.l10n.appTitle,
        theme: AppTheme.lightTheme,
        routerConfig: _router,
        locale: language.locale,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        // Blocks the app while this build is below app_min_version.
        builder: (context, child) => ForceUpdateGate(
          child: SignOutNoticeListener(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}

/// Shown instead of the app when no backend was compiled in.
///
/// Deliberately plain: no providers, no localisation, no router. Those all
/// assume a configured backend, and the one thing this screen must do is
/// render when the rest of the app cannot. It is a build fault rather than
/// a user-facing state, so the text is diagnostic rather than friendly —
/// whoever sees it is whoever can fix it.
class _UnconfiguredApp extends StatelessWidget {
  const _UnconfiguredApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFFE63946),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No backend configured',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'This build has no APPWRITE_ENDPOINT or '
                    'APPWRITE_PROJECT_ID compiled into it, so it cannot '
                    'reach the server. Sign-in and password reset will '
                    'fail with errors that look like server problems.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Rebuild with:\n\n'
                    'flutter build apk --release \\\n'
                    '  --dart-define-from-file=env.json',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
