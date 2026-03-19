import 'package:climate_app/core/services/firebase_service.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/features/verification/screens/verification_detail_screen.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Verification list screen - shows reports pending community verification.
/// Uses Firestore queries — no more Appwrite dependency.
class VerificationListScreen extends StatelessWidget {
  const VerificationListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Get current user ID to exclude their own reports from verification
    final currentUserId = context.read<AuthProvider>().currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify Reports')),
      body: FutureBuilder(
        future: _loadReports(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text(ErrorHandler.getUserMessage(snapshot.error)));
          }

          final reports = snapshot.data ?? [];

          if (reports.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text('No reports pending verification'),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              return ListTile(
                title: Text(report['title'] ?? 'Unknown'),
                subtitle: Text(report['location'] ?? ''),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          VerificationDetailScreen(report: report),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadReports(String? excludeUserId) async {
    try {
      final firebase = FirebaseService();

      final queries = <QueryFilter>[FQuery.equal('status', 'pending')];
      if (excludeUserId != null) {
        queries.add(FQuery.notEqual('userId', excludeUserId));
      }

      final docs = await firebase.listDocuments(
        collectionId: AppConfig.reportsCollection,
        queries: queries,
        limitCount:
            50, // Limit is critical — prevents full-collection scan at scale
      );

      return docs.map((data) {
        data['hazardType'] =
            data['hazardType'] ?? data['title'] ?? 'Unknown Hazard';
        return data;
      }).toList();
    } on Exception {
      return [];
    }
  }
}
