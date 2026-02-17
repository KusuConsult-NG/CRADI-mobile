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

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/alerts')) return 1;
    if (location.startsWith('/knowledge-base')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
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
        context.go('/knowledge-base');
        break;
      case 3:
        context.go('/settings');
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
        bottomNavigationBar: Consumer<LanguageProvider>(
          builder: (context, provider, _) => NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: _onItemTapped,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.grid_view),
                selectedIcon: const Icon(Icons.grid_view_rounded, fill: 1),
                label: provider.navHome,
              ),
              NavigationDestination(
                icon: const Icon(Icons.notifications_outlined),
                selectedIcon: const Icon(Icons.notifications),
                label: provider.navAlerts,
              ),
              NavigationDestination(
                icon: const Icon(Icons.menu_book_outlined),
                selectedIcon: const Icon(Icons.menu_book),
                label: provider.navGuides,
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: provider.navSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
