import 'package:climate_app/features/alerts/screens/alerts_list_screen.dart';
import 'package:climate_app/features/auth/screens/login_screen.dart';
import 'package:climate_app/features/auth/screens/otp_screen.dart';
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
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:climate_app/features/auth/screens/registration_screen.dart';

// Placeholder screens for testing routing
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Splash Screen')));
  }
}

final GoRouter appRouter = GoRouter(
  initialLocation: '/register', // Set to register for UI verification
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegistrationScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/otp',
      builder: (context, state) => const OtpScreen(),
    ),
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
          builder: (context, state) => const AlertsListScreen(),
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
      builder: (context, state) => const VerificationRequestScreen(),
    ),
    GoRoute(
      path: '/reports-status',
      builder: (context, state) => const ReportsStatusScreen(),
    ),
  ],
);
