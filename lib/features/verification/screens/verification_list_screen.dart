import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/services/supabase_service.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/constants/app_config.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/verification/screens/verification_detail_screen.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/reporting/providers/reporting_provider.dart'
    show normalizeSeverity;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/l10n/severity_label.dart';

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
      final auth = context.read<AuthProvider>();
      final statusProvider = context.read<ReportsStatusProvider>();
      final currentUserId = auth.currentUser?.id;
      final db = SupabaseService();

      final queries = <QueryFilter>[
        FQuery.equal('status', 'pending'),
        FQuery.orderDesc('submittedAt'),
      ];
      if (currentUserId != null) {
        // Not neq: that would also drop reports of deleted reporters
        // (user_id NULL).
        queries.add(FQuery.distinctFrom('userId', currentUserId));
      }

      // Own votes (one query, cached) so already-voted reports are hidden.
      final votesFuture = statusProvider.loadMyVotes(force: true);
      final docs = <Map<String, dynamic>>[];
      const page = 100;
      while (docs.length < 1000) {
        final batch = await db.listDocuments(
          collectionId: AppConfig.reportsCollection,
          queries: queries,
          limitCount: page,
          offset: docs.length,
        );
        docs.addAll(batch);
        if (batch.length < page) break;
      }
      await votesFuture;

      // Only reports this user may still vote on (mirrors the database:
      // never one's own, EWMs only in their own LGA and ward).
      final votable = docs.where((d) {
        final id = (d['id'] ?? d['\$id'])?.toString() ?? '';
        return !statusProvider.hasVotedOn(id) &&
            auth.canVoteOn(
              reporterId: d['userId'] as String?,
              reportWard: d['ward'] as String?,
              reportLga: d['lga'] as String?,
            );
      }).toList();

      if (mounted) {
        setState(() {
          _reports = votable;
          _isLoading = false;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = ErrorHandler.getUserMessage(e, context.l10n);
          _isLoading = false;
        });
      }
    }
  }

  String _severityLabel(String? severity) {
    // Tolerate legacy labels such as 'High Severity'.
    final label = severityLabel(context.l10n, severity);
    switch (normalizeSeverity(severity)) {
      case 'critical':
        return '🔴 $label';
      case 'high':
        return '🟠 $label';
      case 'medium':
        return '🟡 $label';
      case 'low':
        return '🟢 $label';
      default:
        return label;
    }
  }

  Color _severityColor(String? severity) {
    switch (normalizeSeverity(severity)) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.deepOrange;
      case 'medium':
        return Colors.amber.shade700;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  /// Roles allowed on /verification/request (see app_router).
  static bool _canRequestVerification(UserRole? role) =>
      AuthProvider.verificationRequestRoles.contains(role);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.homeVerifyReportsLink,
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_canRequestVerification(context.watch<AuthProvider>().userRole))
            IconButton(
              tooltip: context.l10n.verificationListRequestTooltip,
              icon: const Icon(Icons.add_task),
              onPressed: () => context.push('/verification/request'),
            ),
        ],
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
                    label: Text(context.l10n.retry),
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
                    context.l10n.verificationListEmpty,
                    style: GoogleFonts.lexend(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _loadReports,
                    icon: const Icon(Icons.refresh),
                    label: Text(context.l10n.refresh),
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
                  final hazard = Hazard.labelFor(
                    report['hazardType'],
                    context.l10n,
                  );
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
                          Hazard.iconFor(report['hazardType']),
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
