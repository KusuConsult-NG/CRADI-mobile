import 'package:climate_app/core/services/offline_storage_service.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/shared/widgets/app_card.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

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
              'You can still view your saved guides and draft reports.',
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
                  return ListView.builder(
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
                  );
                },
              ),
            ),

            const Spacer(),

            CustomButton(
              text: 'Try Reconnecting & Sync',
              onPressed: () async {
                final connectivityResult = await Connectivity()
                    .checkConnectivity();
                if (connectivityResult == ConnectivityResult.none) {
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

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Syncing pending data...')),
                  );

                  final result = await context
                      .read<ReportingProvider>()
                      .syncPendingReports(context);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result['message']),
                        backgroundColor: result['success']
                            ? Colors.green
                            : AppColors.primaryRed,
                      ),
                    );

                    // Refresh the list if sync happened
                    if (result['success'] && result['synced'] > 0) {
                      setState(() {});
                    }
                  }
                }
              },
            ),
            const SizedBox(height: 16),
            CustomButton(
              text: 'Go to Dashboard',
              type: ButtonType.secondary,
              onPressed: () => context.go('/dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
