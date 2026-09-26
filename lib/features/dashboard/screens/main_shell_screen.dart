import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/widgets/connectivity_banner.dart';
import 'package:flutter/material.dart';
import 'package:climate_app/core/providers/language_provider.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:go_router/go_router.dart';

class MainShellScreen extends StatefulWidget {
  final Widget child;
  const MainShellScreen({super.key, required this.child});

  /// Bottom-nav index for [location]. Always a valid index for a bar with
  /// [destinationCount] entries: a location whose tab is not rendered (e.g.
  /// /admin right after a role change) falls back to Home.
  static int selectedIndexFor(
    String location, {
    required int destinationCount,
  }) {
    bool under(String p) => location == p || location.startsWith('$p/');
    final int index;
    if (under('/dashboard')) {
      index = 0;
    } else if (under('/alerts')) {
      index = 1;
    } else if (under('/report')) {
      index = 2;
    } else if (under('/settings')) {
      index = 3;
    } else if (under('/admin')) {
      index = 4;
    } else {
      index = 0;
    }
    return index < destinationCount ? index : 0;
  }

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  bool _showAdminTab(AuthProvider auth) =>
      auth.userRole == UserRole.admin || auth.userRole == UserRole.techSupport;

  int _calculateSelectedIndex(BuildContext context) {
    final showAdmin = _showAdminTab(context.read<AuthProvider>());
    return MainShellScreen.selectedIndexFor(
      GoRouterState.of(context).uri.path,
      destinationCount: showAdmin ? 5 : 4,
    );
  }

  void _onItemTapped(int index) {
    switch (index) {
      case 0:
        context.go('/dashboard');
        break;
      case 1:
        context.go('/alerts');
        break;
      case 2:
        context.go('/report');
        break;
      case 3:
        context.go('/settings');
        break;
      case 4:
        context.go('/admin');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final int selectedIndex = _calculateSelectedIndex(context);

    // Using PopScope for Android Back Button handling (Flutter 3.12+)
    return PopScope(
      canPop: selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (selectedIndex != 0) {
          context.go('/dashboard');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('CRADI Early Warning'),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications),
              onPressed: () => context.push('/notifications'),
            ),
          ],
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Consumer<ProfileProvider>(
                builder: (context, profileProvider, _) {
                  final initials = profileProvider.name.isNotEmpty
                      ? profileProvider.name
                            .split(' ')
                            .take(2)
                            .map((e) => e.isNotEmpty ? e[0] : '')
                            .join()
                      : 'U';

                  return UserAccountsDrawerHeader(
                    decoration: const BoxDecoration(
                      color: AppColors.primaryRed,
                    ),
                    accountName: Text(
                      profileProvider.name.isNotEmpty
                          ? profileProvider.name
                          : "Early Warning Monitor",
                    ),
                    accountEmail: Text(
                      profileProvider.email.isNotEmpty
                          ? profileProvider.email
                          : "user@cradi.org",
                    ),
                    currentAccountPicture: CircleAvatar(
                      backgroundColor: Colors.white,
                      child: Text(
                        initials.toUpperCase(),
                        style: const TextStyle(color: AppColors.primaryRed),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Profile'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/profile');
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  context.go('/settings');
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () async {
                  Navigator.pop(context);
                  context.read<ProfileProvider>().clearProfile();
                  await context.read<AuthProvider>().logout();
                  if (context.mounted) {
                    context.go('/login');
                  }
                },
              ),
            ],
          ),
        ),
        body: ConnectivityBanner(child: widget.child),
        bottomNavigationBar: Consumer2<LanguageProvider, AuthProvider>(
          builder: (context, langProvider, authProvider, _) {
            final isAdmin = _showAdminTab(authProvider);
            return NavigationBar(
              selectedIndex: MainShellScreen.selectedIndexFor(
                GoRouterState.of(context).uri.path,
                destinationCount: isAdmin ? 5 : 4,
              ),
              onDestinationSelected: _onItemTapped,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.grid_view),
                  selectedIcon: const Icon(Icons.grid_view_rounded, fill: 1),
                  label: langProvider.navHome,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.notifications_outlined),
                  selectedIcon: const Icon(Icons.notifications),
                  label: langProvider.navAlerts,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.add_circle_outline),
                  selectedIcon: const Icon(Icons.add_circle),
                  label: langProvider.navReport,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: langProvider.navSettings,
                ),
                if (isAdmin)
                  const NavigationDestination(
                    icon: Icon(Icons.admin_panel_settings_outlined),
                    selectedIcon: Icon(Icons.admin_panel_settings),
                    label: 'Admin',
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
