import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/shared/widgets/app_card.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';

class OfflineHomeScreen extends StatefulWidget {
  const OfflineHomeScreen({super.key});

  @override
  State<OfflineHomeScreen> createState() => _OfflineHomeScreenState();
}

class _OfflineHomeScreenState extends State<OfflineHomeScreen> {
  String _formatDate(String? isoString) {
    if (isoString == null) return '';
    final date = DateTime.tryParse(isoString);
    if (date == null) return '';
    return DateFormat('MMM d, h:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    // Reporting, settings and guides are signed-in features; a logged-out
    // user would just be bounced to the login screen.
    final isSignedIn = context.select<AuthProvider, bool>(
      (a) => a.isAuthenticated && !a.isLocked,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Mode'),
        backgroundColor: AppColors.primaryGrey,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: AppColors.primaryGrey),
            const SizedBox(height: 16),
            Text(
              'No Internet Connection',
              style: Theme.of(context).textTheme.displayMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isSignedIn
                  ? 'You can still view your saved guides and draft reports.'
                  : 'Reconnect to sign in.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Pending Reports Section
            Text(
              'Pending Reports',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: Future.value(
                  OfflineStorageService().getAllDrafts(),
                ), // Wrapping in future for consistency, though it's sync
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 48,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No pending reports',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    );
                  }

                  final drafts = snapshot.data!;
                  return RefreshIndicator(
                    onRefresh: () async {
                      // Trigger sync check
                      final connectivityProvider = context
                          .read<ConnectivityProvider>();
                      final isOnline = await connectivityProvider
                          .checkConnectivity();

                      if (context.mounted && isOnline) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Syncing pending data...'),
                          ),
                        );
                        await context
                            .read<ReportingProvider>()
                            .syncPendingReports(context);
                        if (context.mounted) {
                          context.go('/dashboard');
                        }
                      }
                      // Refresh UI to show updated drafts
                      setState(() {});
                    },
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: drafts.length,
                      itemBuilder: (context, index) {
                        final draft = drafts[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                            child: ListTile(
                              leading: const Icon(
                                Icons.description,
                                color: AppColors.primaryRed,
                              ),
                              title: Text(
                                draft['hazardType'] ?? 'Unknown Hazard',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                '${draft['locationDetails']}\n${_formatDate(draft['createdAt'])}',
                              ),
                              isThreeLine: true,
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                              ),
                              onTap: () {
                                // Future: Navigate to edit/submit draft
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),

            const Spacer(),

            CustomButton(
              text: 'Try Reconnecting & Sync',
              onPressed: () async {
                final connectivityProvider = context
                    .read<ConnectivityProvider>();

                // Force check connectivity
                final isOnline = await connectivityProvider.checkConnectivity();

                // If manually offline, we should probably tell the user
                if (connectivityProvider.manualOffline) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Offline Mode is enabled in Settings.',
                        ),
                        backgroundColor: Colors.orange,
                        action: isSignedIn
                            ? SnackBarAction(
                                label: 'Settings',
                                onPressed: () => context.push('/settings'),
                                textColor: Colors.white,
                              )
                            : SnackBarAction(
                                label: 'Go online',
                                onPressed: () => connectivityProvider
                                    .setManualOffline(false),
                                textColor: Colors.white,
                              ),
                      ),
                    );
                  }
                }

                if (!isOnline && !connectivityProvider.manualOffline) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Still no internet connection'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                  return;
                }

                if (context.mounted && isOnline) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Syncing pending data...')),
                  );

                  await context.read<ReportingProvider>().syncPendingReports(
                    context,
                  );

                  // refresh UI
                  setState(() {});

                  if (context.mounted) {
                    // If online and synced, suggest going to dashboard
                    context.go('/dashboard');
                  }
                }
              },
            ),
            if (isSignedIn) ...[
              const SizedBox(height: 16),
              CustomButton(
                text: 'Create New Report',
                onPressed: () => context.push('/report'),
                icon: Icons.add_circle_outline,
              ),
              const SizedBox(height: 16),
              CustomButton(
                text: 'Open Settings',
                type: ButtonType.secondary,
                onPressed: () => context.push('/settings'),
                icon: Icons.settings,
              ),
              const SizedBox(height: 16),
              CustomButton(
                text: 'View Saved Guides',
                type: ButtonType.secondary,
                onPressed: () => context.push('/knowledge-base'),
                icon: Icons.menu_book,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
