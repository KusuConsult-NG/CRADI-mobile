import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';

/// Read-only screen that displays full report details.
/// Receives a [VerificationReport] via GoRouter `extra` parameter.
class ReportViewScreen extends StatelessWidget {
  final VerificationReport report;

  const ReportViewScreen({super.key, required this.report});

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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Report Details',
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

            // ── Details Section ───────────────────────────────────────
            _buildSectionCard(
              title: 'Details',
              children: [
                _buildDetailRow(Icons.person, 'Reporter', report.reporter),
                _buildDetailRow(Icons.location_on, 'Location', report.location),
                _buildDetailRow(Icons.access_time, 'Reported', report.time),
                if (report.severity != null)
                  _buildDetailRow(Icons.speed, 'Severity', report.severity!),
                _buildDetailRow(
                  Icons.verified_user,
                  'Verifications',
                  '${report.verificationCount}',
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Description Section ───────────────────────────────────
            if (report.description != null &&
                report.description!.isNotEmpty) ...[
              _buildSectionCard(
                title: 'Description',
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
                title: 'Evidence (${report.imageUrls.length})',
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
                title: 'Coordinates',
                children: [
                  _buildDetailRow(
                    Icons.map,
                    'Latitude',
                    report.latitude!.toStringAsFixed(6),
                  ),
                  _buildDetailRow(
                    Icons.map,
                    'Longitude',
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
                  report.title,
                  style: GoogleFonts.lexend(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  report.type,
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
              report.status.displayName,
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

  Color _getHazardColor(String type) {
    switch (type.toLowerCase()) {
      case 'flooding':
      case 'flood':
        return AppColors.hazardFlood;
      case 'drought':
        return AppColors.hazardDrought;
      case 'fire':
      case 'wildfire':
        return AppColors.hazardFire;
      case 'pest/disease':
      case 'pest':
        return AppColors.hazardPest;
      case 'erosion':
        return AppColors.hazardErosion;
      case 'conflict':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _getHazardIcon(String type) {
    switch (type.toLowerCase()) {
      case 'flooding':
      case 'flood':
        return Icons.flood;
      case 'drought':
        return Icons.wb_sunny;
      case 'fire':
      case 'wildfire':
        return Icons.local_fire_department;
      case 'pest/disease':
      case 'pest':
        return Icons.bug_report;
      case 'erosion':
        return Icons.landscape;
      case 'conflict':
        return Icons.shield;
      default:
        return Icons.warning;
    }
  }
}
