import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/widgets/connectivity_banner.dart';
import 'package:flutter/material.dart';
import 'package:climate_app/core/providers/language_provider.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

class MainShellScreen extends StatefulWidget {
  final Widget child;
  const MainShellScreen({super.key, required this.child});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRADI Early Warning'),
        actions: [
          IconButton(icon: const Icon(Icons.notifications), onPressed: () {}),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: AppColors.primaryRed),
              accountName: Text("Early Warning Monitor"),
              accountEmail: Text("ewm@cradi.org"),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Text(
                  "EW",
                  style: TextStyle(color: AppColors.primaryRed),
                ),
              ),
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
              onTap: () => context.go('/login'),
            ),
          ],
        ),
      ),
      body: ConnectivityBanner(child: widget.child),
      bottomNavigationBar: Consumer<LanguageProvider>(
        builder: (context, provider, _) => NavigationBar(
          selectedIndex: _selectedIndex,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/report'),
        backgroundColor: AppColors.primaryRed,
        icon: const Icon(Icons.add_alert, color: Colors.white),
        label: const Text(
          'REPORT HAZARD',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
