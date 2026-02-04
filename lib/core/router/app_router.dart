import 'package:climate_app/features/alerts/screens/alerts_list_screen.dart';
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
import 'package:climate_app/features/notifications/screens/notifications_screen.dart';
import 'package:climate_app/features/offline_mode/screens/offline_home_screen.dart';
import 'package:climate_app/features/settings/screens/about_app_screen.dart';
import 'package:climate_app/features/settings/screens/help_support_screen.dart';
import 'package:climate_app/features/onboarding/screens/onboarding_screen.dart';
import 'package:climate_app/features/splash/screens/splash_screen.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Create router with authentication guards
GoRouter createRouter(BuildContext context) {
  final authProvider = Provider.of<AuthProvider>(context, listen: false);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (BuildContext context, GoRouterState state) {
      final isAuthenticated = authProvider.isAuthenticated;
      final isLocked = authProvider.isLocked;
      final currentPath = state.matchedLocation;

      // Public routes that don't require authentication
      const publicRoutes = [
        '/splash',
        '/onboarding',
        '/login',
        '/register',
        '/',
      ];

      final isPublicRoute = publicRoutes.contains(currentPath);

      // If trying to access protected route while not authenticated
      if (!isAuthenticated && !isPublicRoute) {
        return '/login';
      }

      // If authenticated but app is locked (biometric enabled)
      if (isAuthenticated && isLocked && !isPublicRoute) {
        // Stay on current screen until unlocked
        // The MainShellScreen handles the biometric prompt
        return null;
      }

      // If authenticated and trying to access auth screens, redirect to dashboard
      if (isAuthenticated &&
          !isLocked &&
          (currentPath == '/login' || currentPath == '/register')) {
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
        builder: (context, state) => const RegistrationScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),

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
              UserRole.coordinator,
              UserRole.projectStaff,
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
                path: 'detail',
                builder: (context, state) {
                  final guide = state.extra as Map<String, dynamic>;
                  return KnowledgeDetailScreen(guide: guide);
                },
              ),
            ],
          ),
        ],
      ),

      // Reporting Routes (Outside Shell to hide bottom nav)
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
        path: '/profile',
        builder: (context, state) => const UserProfileScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/contacts',
        builder: (context, state) => const EmergencyContactsScreen(),
      ),
      GoRoute(
        path: '/knowledge-base/guides',
        builder: (context, state) => const HazardGuidesScreen(),
      ),
      GoRoute(
        path: '/verification/request',
        redirect: (context, state) => _requireRole(context, [
          UserRole.coordinator,
          UserRole.projectStaff,
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

/// Legacy global router for backward compatibility
/// This will be replaced by createRouter() called from main.dart
final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(path: '/', redirect: (context, state) => '/splash'),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegistrationScreen(),
    ),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    ShellRoute(
      builder: (context, state, child) => MainShellScreen(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/verification',
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
              path: 'detail',
              builder: (context, state) {
                final guide = state.extra as Map<String, dynamic>;
                return KnowledgeDetailScreen(guide: guide);
              },
            ),
          ],
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
    GoRoute(
      path: '/profile',
      builder: (context, state) => const UserProfileScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/contacts',
      builder: (context, state) => const EmergencyContactsScreen(),
    ),
    GoRoute(
      path: '/knowledge-base/guides',
      builder: (context, state) => const HazardGuidesScreen(),
    ),
    GoRoute(
      path: '/verification/request',
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
  ],
);
