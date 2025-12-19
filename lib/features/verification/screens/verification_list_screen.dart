import 'package:climate_app/core/services/appwrite_service.dart';
import 'package:appwrite/appwrite.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

/// Verification list screen - shows reports for verification
/// This is a simplified stub implementation using Appwrite
class VerificationListScreen extends StatelessWidget {
  const VerificationListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Reports')),
      body: FutureBuilder(
        future: _loadReports(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
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
                  final alertData = {
                    'title': report['title'],
                    'time': report['time'],
                    'location': report['location'],
                    'icon': Icons
                        .warning, // Fallback if icon mapping not available here
                    'color': Colors.orange,
                    'severity': 'Pending Verification',
                    'status': 'Pending',
                    'description':
                        'Reported by ${report['reporter']}. Type: ${report['type']}',
                  };
                  context.push('/alerts/detail', extra: alertData);
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadReports() async {
    try {
      final appwrite = AppwriteService();
      final docs = await appwrite.listDocuments(
        collectionId: AppwriteService.reportsCollectionId,
        queries: [Query.equal('status', 'pending')],
      );
      return docs.documents.map((doc) => doc.data).toList();
    } on Exception {
      return [];
    }
  }
}
