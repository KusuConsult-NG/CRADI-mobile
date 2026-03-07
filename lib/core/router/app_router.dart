import 'package:climate_app/features/alerts/screens/alerts_list_screen.dart';
import 'package:climate_app/features/auth/screens/landing_screen.dart';
import 'package:climate_app/features/auth/screens/email_verification_screen.dart';

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
import 'package:climate_app/features/reporting/screens/severity_selection_screen.dart';
import 'package:climate_app/features/profile/screens/user_profile_screen.dart';
import 'package:climate_app/features/settings/screens/settings_screen.dart';
import 'package:climate_app/features/verification/screens/verification_list_screen.dart';
import 'package:climate_app/features/verification/screens/reports_status_screen.dart';
import 'package:climate_app/features/verification/screens/verification_request_screen.dart';
import 'package:climate_app/features/auth/screens/registration_screen.dart';
import 'package:climate_app/features/auth/screens/pending_approval_screen.dart';
import 'package:climate_app/features/auth/screens/welcome_screen.dart';
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
import 'package:climate_app/features/admin/screens/admin_screen.dart';
import 'package:climate_app/features/admin/screens/admin_users_screen.dart';
import 'package:climate_app/features/admin/screens/admin_reports_screen.dart';

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
    redirect: (BuildContext context, GoRouterState state) {
      final isInitialized = authProvider.isInitialized;
      final isAuthenticated = authProvider.isAuthenticated;
      final isLocked = authProvider.isLocked;
      final isOffline = connectivityProvider.isOffline;
      final currentPath = state.matchedLocation;

      // 0. Wait for initialization
      if (!isInitialized) {
        // If not initialized, keep showing splash
        return '/splash';
      }

      // 1. Offline check
      // Allow access to Knowledge Base, Settings, and Contacts while offline
      if (isOffline &&
          currentPath != '/offline' &&
          !currentPath.startsWith('/knowledge-base') &&
          !currentPath.startsWith('/settings') &&
          !currentPath.startsWith('/contacts') &&
          !currentPath.startsWith('/report')) {
        return '/offline';
      }

      // If back online and on offline screen, go to dashboard
      if (!isOffline && currentPath == '/offline') {
        return '/dashboard';
      }

      // Public routes that don't require authentication
      const publicRoutes = [
        '/splash',
        '/onboarding',
        '/welcome',
        '/landing',
        '/login',
        '/register',
        '/forgot-password',
        '/reset-password',
        '/pending-approval',
        '/verify-email',
        '/verify-otp',
        '/',
      ];

      final isPublicRoute = publicRoutes.contains(currentPath);

      // 2. Root/Splash Redirect Logic
      // Once initialized, move away from splash
      if (currentPath == '/' || currentPath == '/splash') {
        if (isAuthenticated) {
          if (isLocked) return '/login'; // Or stay on lock screen
          return '/dashboard';
        }

        if (!authProvider.hasCompletedOnboarding) {
          return '/onboarding';
        }
        return '/landing';
      }

      // 3. Protected Route Logic
      // If trying to access protected route while not authenticated
      if (!isAuthenticated && !isPublicRoute) {
        return '/login';
      }

      // If authenticated but app is locked (biometric enabled)
      if (isAuthenticated && isLocked && !isPublicRoute) {
        // Force login/unlock screen if not already there
        // Assuming /login handles the unlock UI or we have a specific /lock screen
        if (currentPath != '/login') {
          return '/login';
        }
        return null;
      }

      // 4. Verification Check
      // If authenticated but NOT verified, force to verification screen
      final isVerified = authProvider.isVerified;

      if (isAuthenticated &&
          !isVerified &&
          currentPath != '/verify-access-code' &&
          currentPath != '/verify-email' &&
          !isPublicRoute) {
        return '/verify-access-code';
      }

      // If IS verified, but trying to go to verification screen, go to dashboard
      if (isAuthenticated &&
          isVerified &&
          currentPath == '/verify-access-code') {
        return '/dashboard';
      }

      return null; // No redirect needed
    },
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
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
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
          final userId = state.uri.queryParameters['userId'] ?? '';
          final secret = state.uri.queryParameters['secret'] ?? '';
          return ResetPasswordScreen(userId: userId, secret: secret);
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
        path: '/verify-email',
        builder: (context, state) {
          final userId = state.uri.queryParameters['userId'] ?? '';
          final secret = state.uri.queryParameters['secret'] ?? '';
          return EmailVerificationScreen(userId: userId, secret: secret);
        },
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
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/verification',
            redirect: (context, state) => _requireRole(context, [
              UserRole.ewv,
              UserRole.ewr,
              UserRole.admin,
              UserRole.techSupport,
            ]),
            builder: (context, state) => const VerificationListScreen(),
          ),
          GoRoute(
            path: '/alerts',
            builder: (context, state) {
              final category = state.extra as String?;
              return AlertsListScreen(initialCategory: category);
            },
            routes: [
              GoRoute(
                path: 'detail',
                builder: (context, state) {
                  final alert = state.extra as Map<String, dynamic>;
                  return AlertDetailScreen(alert: alert);
                },
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
                builder: (context, state) {
                  final guide = state.extra as Map<String, dynamic>;
                  return KnowledgeDetailScreen(guide: guide);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),

      GoRoute(
        path: '/report',
        builder: (context, state) => const HazardSelectionScreen(),
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

      // Profile & Settings
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
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
        builder: (context, state) => const ReportsStatusScreen(),
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
      GoRoute(
        path: '/report/:reportId',
        redirect: (context, state) {
          final auth = Provider.of<AuthProvider>(context, listen: false);
          if (!auth.isAuthenticated) return '/login';
          final id = state.pathParameters['reportId'] ?? '';
          return '/report/details?deepLinkId=$id';
        },
      ),
      GoRoute(
        path: '/alert/:alertId',
        redirect: (context, state) {
          final auth = Provider.of<AuthProvider>(context, listen: false);
          if (!auth.isAuthenticated) return '/login';
          final id = state.pathParameters['alertId'] ?? '';
          return '/alerts/detail?deepLinkId=$id';
        },
      ),
      GoRoute(
        path: '/admin',
        redirect: (context, state) =>
            _requireRole(context, [UserRole.admin, UserRole.techSupport]),
        builder: (context, state) => const AdminScreen(),
        routes: [
          GoRoute(
            path: 'users',
            redirect: (context, state) =>
                _requireRole(context, [UserRole.admin, UserRole.techSupport]),
            builder: (context, state) => const AdminUsersScreen(),
          ),
          GoRoute(
            path: 'reports',
            redirect: (context, state) =>
                _requireRole(context, [UserRole.admin, UserRole.techSupport]),
            builder: (context, state) => const AdminReportsScreen(),
          ),
        ],
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
