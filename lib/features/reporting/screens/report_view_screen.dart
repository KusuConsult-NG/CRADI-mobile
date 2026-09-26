import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/l10n/severity_label.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/widgets/report_staff_actions.dart';
import 'package:climate_app/features/verification/widgets/report_verifications_section.dart';
import 'package:climate_app/features/verification/widgets/report_vote_actions.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// Screen that displays full report details, with the actions the
/// signed-in user may take on it (peer vote, staff approve / reject /
/// reopen), the peer votes (for roles that may read them) and, for a
/// rejected report, the staff's reason.
/// Receives a [VerificationReport] via GoRouter `extra` parameter.
class ReportViewScreen extends StatefulWidget {
  final VerificationReport report;

  const ReportViewScreen({super.key, required this.report});

  @override
  State<ReportViewScreen> createState() => _ReportViewScreenState();
}

class _ReportViewScreenState extends State<ReportViewScreen> {
  late VerificationReport report = widget.report;

  /// Bumped after every reload so the peer votes are re-read too.
  int _reloads = 0;

  @override
  void didUpdateWidget(covariant ReportViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report != widget.report) report = widget.report;
  }

  /// Re-fetches the report after an action changed it.
  Future<void> _reload() async {
    try {
      final fresh = await context.read<ReportsStatusProvider>().fetchReportById(
        report.id,
      );
      if (!mounted) return;
      setState(() {
        if (fresh != null) report = fresh;
        _reloads++;
      });
    } on Exception catch (_) {
      if (mounted) setState(() => _reloads++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: AppColors.textPrimary,
          ),
          // Opened from a notification / deep link there is nothing to pop.
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/reports-status'),
        ),
        title: Text(
          context.l10n.reportDetailsTitle,
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status + Hazard Header ────────────────────────────────
            _buildHeaderCard(),
            const SizedBox(height: 16),

            // ── Rejection reason (shown to the reporter too) ──────────
            if (report.status == ReportStatus.rejected) ...[
              _buildRejectionCard(),
              const SizedBox(height: 16),
            ],

            // ── Peer vote (verification_request pushes open this screen) ──
            ReportVoteActions(report: report, onVoted: _reload),

            // ── Staff approve / reject / reopen ───────────────────────
            ReportStaffActions(report: report, onChanged: _reload),

            // ── Confirmations / disputes with comments (staff) ────────
            ReportVerificationsSection(
              reportId: report.id,
              refreshToken: _reloads,
            ),

            // ── Details Section ───────────────────────────────────────
            _buildSectionCard(
              title: context.l10n.reportViewSectionDetails,
              children: [
                _buildDetailRow(
                  Icons.person,
                  context.l10n.reportViewReporter,
                  report.displayReporter(context.l10n),
                ),
                _buildDetailRow(
                  Icons.location_on,
                  context.l10n.locationLabel,
                  report.displayLocation(context.l10n),
                ),
                _buildDetailRow(
                  Icons.access_time,
                  context.l10n.reportViewReported,
                  report.displayTime(context.l10n),
                ),
                if (report.severity != null)
                  _buildDetailRow(
                    Icons.speed,
                    context.l10n.reportViewSeverity,
                    severityLabel(context.l10n, report.severity),
                  ),
                _buildDetailRow(
                  Icons.verified_user,
                  context.l10n.reportViewVerifications,
                  '${report.verificationCount}',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Description Section ───────────────────────────────────
            if (report.description != null &&
                report.description!.isNotEmpty) ...[
              _buildSectionCard(
                title: context.l10n.descriptionLabel,
                children: [
                  Text(
                    report.description!,
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // ── Evidence Photos ───────────────────────────────────────
            if (report.imageUrls.isNotEmpty) ...[
              _buildSectionCard(
                title: context.l10n.reportViewEvidenceCount(
                  report.imageUrls.length,
                ),
                children: [
                  SizedBox(
                    height: 200,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: report.imageUrls.length,
                      separatorBuilder: (_, index) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            report.imageUrls[index],
                            width: 200,
                            height: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (_, error, stackTrace) => Container(
                              width: 200,
                              height: 200,
                              color: Colors.grey.shade200,
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.grey.shade400,
                                size: 48,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // ── Location Coordinates ──────────────────────────────────
            if (report.latitude != null && report.longitude != null) ...[
              _buildSectionCard(
                title: context.l10n.reportViewCoordinates,
                children: [
                  _buildDetailRow(
                    Icons.map,
                    context.l10n.latitudeLabel,
                    report.latitude!.toStringAsFixed(6),
                  ),
                  _buildDetailRow(
                    Icons.map,
                    context.l10n.longitudeLabel,
                    report.longitude!.toStringAsFixed(6),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Header card with hazard icon + status badge ──────────────────────────

  Widget _buildHeaderCard() {
    final statusColor = _getStatusColor(report.status);
    final hazardColor = _getHazardColor(report.type);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: hazardColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _getHazardIcon(report.type),
              color: hazardColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.displayTitle(context.l10n),
                  style: GoogleFonts.lexend(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Hazard.labelFor(report.type, context.l10n),
                  style: GoogleFonts.lexend(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              report.status.label(context.l10n),
              style: GoogleFonts.lexend(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Rejection reason ────────────────────────────────────────────────────

  Widget _buildRejectionCard() {
    final at = report.rejectedAt;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  at == null
                      ? context.l10n.reportRejectedItem
                      : context.l10n.reportViewRejectedOn(
                          localizedDateFormat(context, 'MMM d, y').format(at),
                        ),
                  style: GoogleFonts.lexend(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  report.rejectionReason ?? context.l10n.reportViewNoReason,
                  style: GoogleFonts.lexend(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section card container ───────────────────────────────────────────────

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.lexend(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  // ── Detail row ───────────────────────────────────────────────────────────

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: GoogleFonts.lexend(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.lexend(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Color _getStatusColor(ReportStatus status) {
    switch (status) {
      case ReportStatus.pending:
        return Colors.orange;
      case ReportStatus.verified:
        return AppColors.successGreen;
      case ReportStatus.approved:
        return Colors.blue;
      case ReportStatus.rejected:
        return Colors.red;
    }
  }

  Color _getHazardColor(String type) => Hazard.colorFor(type);

  IconData _getHazardIcon(String type) => Hazard.iconFor(type);
}
