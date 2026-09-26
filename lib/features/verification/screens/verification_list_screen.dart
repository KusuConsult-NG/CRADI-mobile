import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/verification/screens/verification_detail_screen.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart'
    show normalizeSeverity;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

/// Verification list screen — shows reports pending community verification.
class VerificationListScreen extends StatefulWidget {
  const VerificationListScreen({super.key});

  @override
  State<VerificationListScreen> createState() => _VerificationListScreenState();
}

class _VerificationListScreenState extends State<VerificationListScreen> {
  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUserId = context.read<AuthProvider>().currentUser?.id;
      final db = SupabaseService();

      final queries = <QueryFilter>[FQuery.equal('status', 'pending')];
      if (currentUserId != null) {
        queries.add(FQuery.notEqual('userId', currentUserId));
      }

      final docs = await db.listDocuments(
        collectionId: AppConfig.reportsCollection,
        queries: queries,
        limitCount: 50,
      );

      if (mounted) {
        setState(() {
          _reports = docs;
          _isLoading = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ErrorHandler.getUserMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  String _severityLabel(String? severity) {
    // Tolerate legacy labels such as 'High Severity'.
    switch (normalizeSeverity(severity)) {
      case 'critical':
        return '🔴 Critical';
      case 'high':
        return '🟠 High';
      case 'medium':
        return '🟡 Medium';
      case 'low':
        return '🟢 Low';
      default:
        return severity ?? 'Unknown';
    }
  }

  Color _severityColor(String? severity) {
    switch (normalizeSeverity(severity)) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.amber;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Verify Reports',
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 12),
                  Text(_errorMessage!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadReports,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _reports.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No reports pending verification',
                    style: GoogleFonts.lexend(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _loadReports,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadReports,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _reports.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final report = _reports[index];
                  final hazard = report['hazardType'] ?? 'Unknown Hazard';
                  final severity = report['severity'] as String?;
                  final lga = report['lga'] ?? '';
                  final state = report['state'] ?? '';
                  final subtitle = [
                    lga,
                    state,
                  ].where((s) => s.isNotEmpty).join(', ');

                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _severityColor(
                            severity,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: _severityColor(severity),
                        ),
                      ),
                      title: Text(
                        hazard,
                        style: GoogleFonts.lexend(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              style: GoogleFonts.lexend(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            _severityLabel(severity),
                            style: GoogleFonts.lexend(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _severityColor(severity),
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: AppColors.primaryRed,
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                VerificationDetailScreen(report: report),
                          ),
                        );
                        // Refresh after returning from detail screen
                        _loadReports();
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}
