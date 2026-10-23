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
  /// When [hasReportTab] is false the Report tab is omitted and everything
  /// after it moves up one, so the order is Home(0) Alerts(1) Settings(2)
  /// Admin(3) rather than Home(0) Alerts(1) Report(2) Settings(3) Admin(4).
  static int selectedIndexFor(
    String location, {
    required int destinationCount,
    bool hasReportTab = true,
  }) {
    bool under(String p) => location == p || location.startsWith('$p/');
    final int index;
    if (under('/dashboard')) {
      index = 0;
    } else if (under('/alerts')) {
      index = 1;
    } else if (!hasReportTab) {
      // No Report tab, so Settings is 2 and Admin is 3.
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

  /// Whether the bar draws a Report tab for [role].
  ///
  /// Matrix 4.1 gives neither Early Responder nor tech support Submit
  /// Reports, and the server refuses the write either way
  /// (`guardReportCreate`), so offering the tab would only earn a 403.
  static bool hasReportTabFor(UserRole? role) =>
      role != UserRole.ewr && role != UserRole.techSupport;

  /// Home and Alerts always, Settings always, Report and Admin by role.
  static int tabCountFor({
    required bool showAdmin,
    required bool hasReportTab,
  }) => 3 + (hasReportTab ? 1 : 0) + (showAdmin ? 1 : 0);

  /// The route tab [index] opens, on a bar drawn with [hasReportTab], or
  /// null when that bar has no such tab.
  ///
  /// The inverse of [selectedIndexFor]; the two have to agree on the tab
  /// order, so they are kept together.
  static String? routeForTab(int index, {required bool hasReportTab}) {
    if (!hasReportTab) {
      // Without it: 0=Dashboard 1=Alerts 2=Settings 3=Admin
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

  int _calculateSelectedIndex(BuildContext context, AuthProvider auth) {
    final showAdmin = _showAdminTab(auth);
    final report = MainShellScreen.hasReportTabFor(auth.userRole);
    return MainShellScreen.selectedIndexFor(
      GoRouterState.of(context).uri.path,
      destinationCount: MainShellScreen.tabCountFor(
        showAdmin: showAdmin,
        hasReportTab: report,
      ),
      hasReportTab: report,
    );
  }

  /// [hasReportTab] is the value the bar was *drawn* with, not a fresh
  /// read. Reading the role again here meant a role that changed between
  /// the build and the tap shifted the tab order under the user's finger:
  /// on a bar drawn with a Report tab at 2, a role that had since lost it
  /// sent that tap to /settings instead.
  void _onItemTapped(int index, {required bool hasReportTab}) {
    final route = MainShellScreen.routeForTab(
      index,
      hasReportTab: hasReportTab,
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
            final report = MainShellScreen.hasReportTabFor(
              authProvider.userRole,
            );
            final count = MainShellScreen.tabCountFor(
              showAdmin: isAdmin,
              hasReportTab: report,
            );
            return NavigationBar(
              selectedIndex: MainShellScreen.selectedIndexFor(
                GoRouterState.of(context).uri.path,
                destinationCount: count,
                hasReportTab: report,
              ),
              onDestinationSelected: (index) =>
                  _onItemTapped(index, hasReportTab: report),
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
                // Neither Early Responder nor tech support has Submit
                // Reports under matrix 4.1, so the tab is omitted for them.
                if (report)
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
