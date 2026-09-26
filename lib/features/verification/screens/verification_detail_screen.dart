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
import 'package:climate_app/features/reporting/widgets/osm_location_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/utils/screen_security.dart';

class VerificationDetailScreen extends StatefulWidget {
  final Map<String, dynamic> report;

  const VerificationDetailScreen({super.key, required this.report});

  @override
  State<VerificationDetailScreen> createState() =>
      _VerificationDetailScreenState();
}

/// Label and colour of the status badge for a report [status] value.
@visibleForTesting
(String, Color) statusBadgeFor(String status, AppLocalizations l10n) =>
    switch (status) {
      'verified' ||
      'acknowledged' => (l10n.statusBadgeVerified, Colors.green.shade700),
      'approved' ||
      'validated' ||
      'resolved' => (l10n.statusBadgeApproved, Colors.blue),
      'rejected' => (l10n.statusBadgeRejected, Colors.red),
      _ => (l10n.statusBadgePending, Colors.orange.shade800),
    };

class _VerificationDetailScreenState extends State<VerificationDetailScreen>
    with ScreenSecurityMixin<VerificationDetailScreen> {
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
    final l10n = context.l10n;
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
            isConfirmed ? l10n.voteConfirmedThanks : l10n.voteDisputeRecorded,
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
      messenger.showSnackBar(SnackBar(content: Text(e.message(l10n))));
      // Nothing left to do here: back to the (refreshed) list.
      if (closed && context.canPop()) context.pop();
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ErrorHandler.handleError(e, l10n, context: 'Verification'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final lat = double.tryParse('${report['latitude']}');
    final lng = double.tryParse('${report['longitude']}');
    final reportLatLng = (lat != null && lng != null) ? LatLng(lat, lng) : null;
    // Stored in UTC; show the device's local time.
    final date = parseTimestamp(report['submittedAt']);
    final formattedDate = date == null
        ? context.l10n.verificationDetailUnknownTime
        : localizedDateFormat(context, 'MMM d, y • h:mm a').format(date);
    final status = (report['status'] ?? 'pending').toString().toLowerCase();
    final (badgeLabel, badgeColor) = statusBadgeFor(status, context.l10n);
    final canVote = status == 'pending' && !_votingClosed;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(context.l10n.verificationDetailTitle),
        leading: IconButton(
          tooltip: context.l10n.back,
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
              child: Semantics(
                label: context.l10n.a11yStatusLabel(badgeLabel),
                excludeSemantics: true,
                child: Text(
                  badgeLabel,
                  style: GoogleFonts.lexend(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Info
            Text(
              Hazard.labelFor(report['hazardType'], context.l10n),
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
                    report['locationDetails'] ??
                        context.l10n.verificationDetailNoLocation,
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
              context.l10n.descriptionLabel,
              style: GoogleFonts.lexend(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              (report['description'] as String?)?.trim().isNotEmpty == true
                  ? report['description'] as String
                  : context.l10n.noDescriptionProvided,
              style: GoogleFonts.lexend(
                fontSize: 14,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 24),

            // Report location on a (read-only) map, when it has coordinates.
            if (reportLatLng != null)
              SizedBox(
                height: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: OSMLocationPicker(
                    initialPosition: reportLatLng,
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
                        context.l10n.verificationDetailNoMap,
                        style: GoogleFonts.lexend(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 32),

            // Verification Actions
            Text(
              context.l10n.verificationDetailQuestion,
              style: GoogleFonts.lexend(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.verificationDetailInstructions,
              style: GoogleFonts.lexend(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              enabled: canVote,
              decoration: InputDecoration(
                labelText: context.l10n.alertDetailCommentLabel,
                border: const OutlineInputBorder(),
                hintText: context.l10n.verificationDetailCommentHint,
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    text: context.l10n.voteDispute,
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
                    text: context.l10n.verificationDetailConfirm,
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
