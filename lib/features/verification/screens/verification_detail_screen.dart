import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/services/supabase_service.dart'
    show parseTimestamp;
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/widgets/dispute_comment_dialog.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:climate_app/features/reporting/widgets/osm_location_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

class VerificationDetailScreen extends StatefulWidget {
  final Map<String, dynamic> report;

  const VerificationDetailScreen({super.key, required this.report});

  @override
  State<VerificationDetailScreen> createState() =>
      _VerificationDetailScreenState();
}

/// Label and colour of the status badge for a report [status] value.
@visibleForTesting
(String, Color) statusBadgeFor(String status) => switch (status) {
  'verified' || 'acknowledged' => ('VERIFIED', Colors.green.shade700),
  'approved' || 'validated' || 'resolved' => ('APPROVED', Colors.blue),
  'rejected' => ('REJECTED', Colors.red),
  _ => ('PENDING VERIFICATION', Colors.orange.shade800),
};

class _VerificationDetailScreenState extends State<VerificationDetailScreen> {
  bool _isLoading = false;

  /// Set once voting is no longer possible (already voted, or the report
  /// left 'pending'): the buttons are disabled.
  bool _votingClosed = false;
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitVerification(bool isConfirmed) async {
    final reportId = (widget.report['\$id'] ?? widget.report['id'])?.toString();
    if (reportId == null || reportId.isEmpty) return;
    // A dispute must say what is wrong with the report.
    var comment = _commentController.text.trim();
    if (!isConfirmed && comment.isEmpty) {
      final entered = await showDisputeCommentDialog(context);
      if (entered == null || !mounted) return;
      comment = entered;
      _commentController.text = entered;
    }
    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<ReportsStatusProvider>();

    try {
      // Goes through the provider so the "already voted" cache and the
      // loaded lists are updated.
      if (isConfirmed) {
        await provider.verifyReport(
          reportId,
          comment: comment.isEmpty ? null : comment,
        );
      } else {
        await provider.disputeReport(reportId, comment: comment);
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isConfirmed
                ? 'Report confirmed. Thank you!'
                : 'Dispute recorded. Staff will review the report.',
          ),
          backgroundColor: isConfirmed ? Colors.green : Colors.orange,
        ),
      );
      context.pop(); // Go back to list
    } on VerificationRefusedException catch (e) {
      if (!mounted) return;
      final closed = e.alreadyVoted || e.noLongerPending;
      setState(() {
        _isLoading = false;
        if (closed) _votingClosed = true;
      });
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      // Nothing left to do here: back to the (refreshed) list.
      if (closed && context.canPop()) context.pop();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(ErrorHandler.handleError(e, context: 'Verification')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    // Stored in UTC; show the device's local time.
    final date = parseTimestamp(report['submittedAt']);
    final formattedDate = date == null
        ? 'Unknown time'
        : DateFormat('MMM d, y • h:mm a').format(date);
    final status = (report['status'] ?? 'pending').toString().toLowerCase();
    final (badgeLabel, badgeColor) = statusBadgeFor(status);
    final canVote = status == 'pending' && !_votingClosed;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Verify Report'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Badge (the report's actual status)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: badgeColor),
              ),
              child: Text(
                badgeLabel,
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: badgeColor,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Info
            Text(
              Hazard.labelFor(report['hazardType']),
              style: GoogleFonts.lexend(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    report['locationDetails'] ?? 'No location details',
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.access_time,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  formattedDate,
                  style: GoogleFonts.lexend(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Description
            Text(
              'Description',
              style: GoogleFonts.lexend(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              report['description'] ?? 'No description provided.',
              style: GoogleFonts.lexend(
                fontSize: 14,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 24),

            // Map Placeholder (In real app, show map)
            // Map View
            if (report['latitude'] != null && report['longitude'] != null)
              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: OSMLocationPicker(
                    initialPosition: LatLng(
                      double.tryParse(report['latitude'].toString()) ?? 0,
                      double.tryParse(report['longitude'].toString()) ?? 0,
                    ),
                    isInteractive: false,
                  ),
                ),
              )
            else
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_off,
                        size: 40,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No map location available',
                        style: GoogleFonts.lexend(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 32),

            // Verification Actions
            Text(
              'Can you confirm this report?',
              style: GoogleFonts.lexend(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Please verify if you have observed this hazard in the reported location.',
              style: GoogleFonts.lexend(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              enabled: canVote,
              decoration: const InputDecoration(
                labelText: 'Comment (required to dispute)',
                border: OutlineInputBorder(),
                hintText: 'Add details about what you see...',
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: 'Dispute',
                    onPressed: _isLoading || !canVote
                        ? null
                        : () => _submitVerification(false),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    type: ButtonType.secondary,
                    isLoading: _isLoading,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomButton(
                    text: 'I Can Confirm',
                    onPressed: _isLoading || !canVote
                        ? null
                        : () => _submitVerification(true),
                    backgroundColor: Colors.green,
                    isLoading: _isLoading,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
