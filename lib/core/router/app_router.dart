import 'package:climate_app/features/alerts/screens/alerts_list_screen.dart';
import 'package:climate_app/features/auth/screens/landing_screen.dart';

import 'package:climate_app/features/alerts/screens/alert_detail_screen.dart';
import 'package:climate_app/features/auth/screens/login_screen.dart';
import 'package:climate_app/features/chat/screens/chat_screen.dart';
import 'package:climate_app/features/contacts/screens/emergency_contacts_screen.dart';
import 'package:climate_app/features/dashboard/screens/home_screen.dart';
import 'package:climate_app/features/dashboard/screens/main_shell_screen.dart';
import 'package:climate_app/features/knowledge_base/screens/hazard_guides_screen.dart';
import 'package:climate_app/features/knowledge_base/screens/knowledge_base_screen.dart';
import 'package:climate_app/features/knowledge_base/screens/knowledge_detail_screen.dart';
import 'package:climate_app/features/reporting/screens/hazard_selection_screen.dart';
import 'package:climate_app/features/reporting/screens/location_picker_screen.dart';
import 'package:climate_app/features/reporting/screens/report_details_screen.dart';
import 'package:climate_app/features/reporting/screens/report_review_screen.dart';
import 'package:climate_app/features/reporting/screens/report_view_screen.dart';
import 'package:climate_app/features/reporting/screens/my_reports_screen.dart';
import 'package:climate_app/features/reporting/screens/nearby_reports_screen.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/reporting/screens/severity_selection_screen.dart';
import 'package:climate_app/features/profile/screens/user_profile_screen.dart';
import 'package:climate_app/features/settings/screens/settings_screen.dart';
import 'package:climate_app/features/verification/screens/verification_list_screen.dart';
import 'package:climate_app/features/verification/screens/reports_status_screen.dart';
import 'package:climate_app/features/verification/screens/verification_request_screen.dart';
import 'package:climate_app/features/auth/screens/registration_screen.dart';
import 'package:climate_app/features/auth/screens/pending_approval_screen.dart';
import 'package:climate_app/features/auth/screens/forgot_password_screen.dart';
import 'package:climate_app/features/auth/screens/reset_password_screen.dart';
import 'package:climate_app/features/notifications/screens/notifications_screen.dart';
import 'package:climate_app/features/offline_mode/screens/offline_home_screen.dart';
import 'package:climate_app/features/settings/screens/about_app_screen.dart';
import 'package:climate_app/features/settings/screens/help_support_screen.dart';
import 'package:climate_app/features/onboarding/screens/onboarding_screen.dart';
import 'package:climate_app/features/splash/screens/splash_screen.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/auth/screens/access_code_verification_screen.dart';
import 'package:climate_app/features/auth/screens/otp_verification_screen.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/core/router/route_guard.dart';
import 'package:climate_app/core/widgets/route_status_screen.dart';
import 'package:climate_app/features/alerts/providers/alerts_provider.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/admin/screens/admin_screen.dart';
import 'package:climate_app/features/admin/screens/admin_users_screen.dart';
import 'package:climate_app/features/admin/screens/admin_reports_screen.dart';
import 'package:climate_app/features/admin/screens/admin_alerts_screen.dart';
import 'package:climate_app/features/admin/screens/admin_knowledge_screen.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Create router with authentication guards
GoRouter createRouter(BuildContext context) {
  final authProvider = Provider.of<AuthProvider>(context, listen: false);
  final connectivityProvider = Provider.of<ConnectivityProvider>(
    context,
    listen: false,
  );

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: Listenable.merge([authProvider, connectivityProvider]),
    errorBuilder: (context, state) => const RouteStatusScreen.notFound(),
    redirect: (BuildContext context, GoRouterState state) => resolveRedirect(
      RouteGuardState(
        isInitialized: authProvider.isInitialized,
        isAuthenticated: authProvider.isAuthenticated,
        isLocked: authProvider.isLocked,
        isOffline: connectivityProvider.isOffline,
        isVerified: authProvider.isVerified,
        isApproved: authProvider.isApproved,
        hasCompletedOnboarding: authProvider.hasCompletedOnboarding,
      ),
      state.uri,
    ),
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(path: '/', redirect: (context, state) => '/splash'),
      GoRoute(
        path: '/register',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return RegistrationScreen(
            prefilledEmail: extra?['email'],
            isVerified: extra?['isVerified'] ?? false,
          );
        },
      ),

      GoRoute(
        path: '/landing',
        builder: (context, state) => const LandingScreen(),
      ),

      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) {
          // Recovery uses the 6-digit code Supabase emails; the screen
          // collects it together with the new password.
          final email = state.uri.queryParameters['email'] ?? '';
          return ResetPasswordScreen(email: email);
        },
      ),
      GoRoute(
        path: '/pending-approval',
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: '/verify-access-code',
        builder: (context, state) => const AccessCodeVerificationScreen(),
      ),
      GoRoute(
        path: '/verify-otp',
        builder: (context, state) {
          final phone = state.uri.queryParameters['phone'] ?? '';
          final extra = state.extra as Map<String, dynamic>?;
          return OtpVerificationScreen(
            phoneNumber: phone,
            registrationData: extra,
          );
        },
      ),

      // Protected routes with Shell
      ShellRoute(
        builder: (context, state, child) => MainShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => _buildTransitionPage(
              context: context,
              state: state,
              child: const HomeScreen(),
            ),
          ),
          GoRoute(
            path: '/verification',
            // Peer verifiers (is_verifier()) — the list is for casting votes.
            redirect: (context, state) =>
                _requireRole(context, AuthProvider.verifierRoles.toList()),
            builder: (context, state) => const VerificationListScreen(),
          ),
          GoRoute(
            path: '/alerts',
            pageBuilder: (context, state) {
              // go_router shares `extra` with parent matches: a push to
              // /alerts/detail hands this page the alert Map.
              final extra = state.extra;
              final category = extra is String ? extra : null;
              return _buildTransitionPage(
                context: context,
                state: state,
                child: AlertsListScreen(initialCategory: category),
              );
            },
            routes: [
              GoRoute(
                path: 'detail',
                // In-app navigation passes the alert via extra; deep links /
                // state restoration arrive without it.
                redirect: (context, state) =>
                    state.extra is Map<String, dynamic> ? null : '/alerts',
                builder: (context, state) => AlertDetailScreen(
                  alert: state.extra as Map<String, dynamic>,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/report',
            pageBuilder: (context, state) => _buildTransitionPage(
              context: context,
              state: state,
              child: const HazardSelectionScreen(),
            ),
            routes: [
              GoRoute(
                path: 'severity',
                builder: (context, state) => const SeveritySelectionScreen(),
              ),
              GoRoute(
                path: 'location',
                builder: (context, state) => const LocationPickerScreen(),
              ),
              GoRoute(
                path: 'details',
                builder: (context, state) => const ReportDetailsScreen(),
              ),
              GoRoute(
                path: 'review',
                builder: (context, state) => const ReportReviewScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/my-reports',
            pageBuilder: (context, state) => _buildTransitionPage(
              context: context,
              state: state,
              child: const MyReportsScreen(),
            ),
          ),
          GoRoute(
            path: '/nearby-reports',
            pageBuilder: (context, state) => _buildTransitionPage(
              context: context,
              state: state,
              child: const NearbyReportsScreen(),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => _buildTransitionPage(
              context: context,
              state: state,
              child: const SettingsScreen(),
            ),
          ),
          GoRoute(
            path: '/admin',
            redirect: (context, state) =>
                _requireRole(context, [UserRole.admin, UserRole.techSupport]),
            pageBuilder: (context, state) => _buildTransitionPage(
              context: context,
              state: state,
              child: const AdminScreen(),
            ),
            routes: [
              GoRoute(
                path: 'users',
                // Profile writes (approve / role / disable) are admin-only
                // in the database.
                redirect: (context, state) =>
                    _requireRole(context, [UserRole.admin]),
                builder: (context, state) => AdminUsersScreen(
                  pendingOnly: state.uri.queryParameters['filter'] == 'pending',
                ),
              ),
              GoRoute(
                path: 'reports',
                redirect: (context, state) => _requireRole(context, [
                  UserRole.admin,
                  UserRole.techSupport,
                ]),
                builder: (context, state) => const AdminReportsScreen(),
              ),
              GoRoute(
                path: 'alerts',
                redirect: (context, state) => _requireRole(context, [
                  UserRole.admin,
                  UserRole.techSupport,
                ]),
                builder: (context, state) => const AdminAlertsScreen(),
              ),
              GoRoute(
                path: 'knowledge',
                redirect: (context, state) => _requireRole(context, [
                  UserRole.admin,
                  UserRole.techSupport,
                ]),
                builder: (context, state) => const AdminKnowledgeScreen(),
              ),
            ],
          ),
        ],
      ),

      GoRoute(
        path: '/knowledge-base',
        builder: (context, state) => const KnowledgeBaseScreen(),
        routes: [
          GoRoute(
            path: 'guides',
            builder: (context, state) {
              final category = state.extra as String?;
              return HazardGuidesScreen(initialCategory: category);
            },
          ),
          GoRoute(
            path: 'detail',
            // Deep links / state restoration arrive without `extra`.
            redirect: (context, state) =>
                state.extra is Map<String, dynamic> ? null : '/knowledge-base',
            builder: (context, state) {
              final guide = state.extra as Map<String, dynamic>?;
              if (guide == null) return const KnowledgeBaseScreen();
              return KnowledgeDetailScreen(guide: guide);
            },
          ),
        ],
      ),

      // Profile & Settings
      GoRoute(
        path: '/profile',
        builder: (context, state) => const UserProfileScreen(),
      ),
      GoRoute(
        path: '/contacts',
        builder: (context, state) => const EmergencyContactsScreen(),
      ),
      GoRoute(
        path: '/verification/request',
        redirect: (context, state) => _requireRole(context, [
          UserRole.ewv,
          UserRole.ewr,
          UserRole.admin,
          UserRole.techSupport,
        ]),
        builder: (context, state) => const VerificationRequestScreen(),
      ),
      GoRoute(
        path: '/reports-status',
        builder: (context, state) =>
            ReportsStatusScreen(initialTab: state.uri.queryParameters['tab']),
      ),
      GoRoute(
        path: '/report-view',
        // Deep links / state restoration arrive without `extra`.
        redirect: (context, state) =>
            state.extra is VerificationReport ? null : '/reports-status',
        builder: (context, state) {
          final report = state.extra as VerificationReport?;
          if (report == null) return const ReportsStatusScreen();
          return ReportViewScreen(report: report);
        },
      ),
      GoRoute(path: '/chat', builder: (context, state) => const ChatScreen()),
      GoRoute(
        path: '/offline',
        builder: (context, state) => const OfflineHomeScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/help',
        builder: (context, state) => const HelpSupportScreen(),
      ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const AboutAppScreen(),
      ),
      // ── Deep Link Routes ───────────────────────────────────────────────────
      // Push notifications (OneSignal additionalData) and shared links
      // (cradi://report/<id>) open a specific report / alert. Sign-in is
      // enforced by the top-level redirect.
      GoRoute(
        path: '/report/:reportId',
        builder: (context, state) {
          final id = state.pathParameters['reportId']!;
          return DeepLinkLoader<VerificationReport>(
            key: ValueKey('report-$id'),
            load: () =>
                context.read<ReportsStatusProvider>().fetchReportById(id),
            builder: (context, report) => ReportViewScreen(report: report),
            notFoundTitle: 'Report not found',
            fallbackLocation: '/reports-status',
            fallbackLabel: 'View reports',
          );
        },
      ),
      GoRoute(
        path: '/alert/:alertId',
        builder: (context, state) {
          final id = state.pathParameters['alertId']!;
          return DeepLinkLoader<Map<String, dynamic>>(
            key: ValueKey('alert-$id'),
            load: () => context.read<AlertsProvider>().fetchAlertById(id),
            builder: (context, alert) => AlertDetailScreen(alert: alert),
            notFoundTitle: 'Alert not found',
            fallbackLocation: '/alerts',
            fallbackLabel: 'View alerts',
          );
        },
      ),
    ],
  );
}

/// Helper function to check role-based access
String? _requireRole(BuildContext context, List<UserRole> allowedRoles) {
  final authProvider = Provider.of<AuthProvider>(context, listen: false);
  final userRole = authProvider.userRole;

  if (userRole == null || !allowedRoles.contains(userRole)) {
    // User doesn't have required role, redirect to dashboard
    return '/dashboard';
  }

  return null; // Allow access
}

// NOTE: Use createRouter(context) from main.dart — this file no longer exports
// a global router. The legacy appRouter has been removed.

Widget _buildPageTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  const curve = Curves.easeOutCubic;
  final slideAnimation = Tween(
    begin: const Offset(0.0, 0.05),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: animation, curve: curve));

  final fadeAnimation = Tween(
    begin: 0.0,
    end: 1.0,
  ).animate(CurvedAnimation(parent: animation, curve: curve));

  return FadeTransition(
    opacity: fadeAnimation,
    child: SlideTransition(position: slideAnimation, child: child),
  );
}

CustomTransitionPage<T> _buildTransitionPage<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    // Unique per navigation: pushing the same location twice must not
    // produce duplicate page keys.
    key: state.pageKey,
    child: child,
    transitionsBuilder: _buildPageTransition,
    transitionDuration: const Duration(milliseconds: 300),
  );
}
