import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/widgets/connectivity_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:climate_app/core/l10n/l10n.dart';

class MainShellScreen extends StatefulWidget {
  final Widget child;
  const MainShellScreen({super.key, required this.child});

  /// Bottom-nav index for [location]. Always a valid index for a bar with
  /// [destinationCount] entries: a location whose tab is not rendered (e.g.
  /// /admin right after a role change) falls back to Home.
  ///
  /// When [isTechSupport] is true, the Report tab is omitted and Admin takes
  /// its logical slot, so the tab order is: Home(0) Alerts(1) Settings(2) Admin(3).
  static int selectedIndexFor(
    String location, {
    required int destinationCount,
    bool isTechSupport = false,
  }) {
    bool under(String p) => location == p || location.startsWith('$p/');
    final int index;
    if (under('/dashboard')) {
      index = 0;
    } else if (under('/alerts')) {
      index = 1;
    } else if (isTechSupport) {
      // techSupport has no Report tab — Settings is 2, Admin is 3.
      if (under('/settings')) {
        index = 2;
      } else if (under('/admin')) {
        index = 3;
      } else {
        index = 0;
      }
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

  /// The route tab [index] opens, on a bar drawn for [isTechSupport], or
  /// null when that bar has no such tab.
  ///
  /// The inverse of [selectedIndexFor]; the two have to agree on the tab
  /// order, so they are kept together.
  static String? routeForTab(int index, {required bool isTechSupport}) {
    if (isTechSupport) {
      // techSupport tab order: 0=Dashboard 1=Alerts 2=Settings 3=Admin
      const routes = ['/dashboard', '/alerts', '/settings', '/admin'];
      return index >= 0 && index < routes.length ? routes[index] : null;
    }
    // Standard tab order: 0=Dashboard 1=Alerts 2=Report 3=Settings [4=Admin]
    const routes = ['/dashboard', '/alerts', '/report', '/settings', '/admin'];
    return index >= 0 && index < routes.length ? routes[index] : null;
  }

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  bool _showAdminTab(AuthProvider auth) =>
      auth.userRole == UserRole.admin || auth.userRole == UserRole.techSupport;

  bool _isTechSupport(AuthProvider auth) =>
      auth.userRole == UserRole.techSupport;

  int _calculateSelectedIndex(BuildContext context, AuthProvider auth) {
    final showAdmin = _showAdminTab(auth);
    final techSupport = _isTechSupport(auth);
    // techSupport: 4 tabs (no Report). admin: 5 tabs. others: 4 tabs (no Admin).
    final count = showAdmin ? (techSupport ? 4 : 5) : 4;
    return MainShellScreen.selectedIndexFor(
      GoRouterState.of(context).uri.path,
      destinationCount: count,
      isTechSupport: techSupport,
    );
  }

  /// [isTechSupport] is the value the bar was *drawn* with, not a fresh
  /// read. Reading the role again here meant a role that changed between
  /// the build and the tap shifted the tab order under the user's finger:
  /// on a bar drawn with a Report tab at 2, a role that had since become
  /// techSupport sent that tap to /settings instead.
  void _onItemTapped(int index, {required bool isTechSupport}) {
    final route = MainShellScreen.routeForTab(
      index,
      isTechSupport: isTechSupport,
    );
    if (route != null) context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    // `watch`, not `read`: the shell has to redraw when the role resolves,
    // or the back-button handling below keeps the index it was first built
    // with.
    final auth = context.watch<AuthProvider>();
    final int selectedIndex = _calculateSelectedIndex(context, auth);

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
          title: Text(context.l10n.shellAppBarTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications),
              tooltip: context.l10n.shellNotificationsTooltip,
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
                          : context.l10n.shellDrawerDefaultName,
                    ),
                    // No placeholder address: the line is left out until
                    // the profile's email is known.
                    accountEmail: profileProvider.email.isNotEmpty
                        ? Text(profileProvider.email)
                        : null,
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
                title: Text(context.l10n.shellDrawerProfile),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/profile');
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: Text(context.l10n.navSettings),
                onTap: () {
                  Navigator.pop(context);
                  context.go('/settings');
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(context.l10n.logout),
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
        bottomNavigationBar: Consumer<AuthProvider>(
          builder: (context, authProvider, _) {
            final l10n = context.l10n;
            final isAdmin = _showAdminTab(authProvider);
            final techSupport = _isTechSupport(authProvider);
            // techSupport: 4 tabs (no Report). admin: 5 tabs. others: 4 tabs.
            final count = isAdmin ? (techSupport ? 4 : 5) : 4;
            return NavigationBar(
              selectedIndex: MainShellScreen.selectedIndexFor(
                GoRouterState.of(context).uri.path,
                destinationCount: count,
                isTechSupport: techSupport,
              ),
              onDestinationSelected: (index) =>
                  _onItemTapped(index, isTechSupport: techSupport),
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.grid_view),
                  selectedIcon: const Icon(Icons.grid_view_rounded, fill: 1),
                  label: l10n.navHome,
                ),
                NavigationDestination(
                  icon: const Icon(Icons.notifications_outlined),
                  selectedIcon: const Icon(Icons.notifications),
                  label: l10n.navAlerts,
                ),
                // techSupport does not have reporting access — the Report tab
                // is omitted for that role.
                if (!techSupport)
                  NavigationDestination(
                    icon: const Icon(Icons.add_circle_outline),
                    selectedIcon: const Icon(Icons.add_circle),
                    label: l10n.navReport,
                  ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings),
                  label: l10n.navSettings,
                ),
                if (isAdmin)
                  NavigationDestination(
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    selectedIcon: const Icon(Icons.admin_panel_settings),
                    label: l10n.navAdmin,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
