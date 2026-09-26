import 'dart:async';

import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/widgets/dispute_comment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// Confirm / Dispute peer-vote buttons for a pending report, shown only
/// when the signed-in user may vote on it (same rules as the database) and
/// has not voted yet. Used on the report screen that a
/// `verification_request` push opens.
class ReportVoteActions extends StatefulWidget {
  const ReportVoteActions({super.key, required this.report, this.onVoted});

  final VerificationReport report;

  /// Called after a vote was recorded (e.g. to reload the report).
  final VoidCallback? onVoted;

  @override
  State<ReportVoteActions> createState() => _ReportVoteActionsState();
}

class _ReportVoteActionsState extends State<ReportVoteActions> {
  bool _submitting = false;

  /// Set when the server said the report is no longer pending: the
  /// [VerificationReport] passed in is stale, so hide the buttons.
  bool _noLongerPending = false;

  @override
  void initState() {
    super.initState();
    // hasVotedOn needs the user's votes; they may not be loaded yet when
    // this screen is opened straight from a push notification.
    unawaited(context.read<ReportsStatusProvider>().loadMyVotes());
  }

  static bool canVote(
    AuthProvider auth,
    ReportsStatusProvider reports,
    VerificationReport report,
  ) =>
      report.status == ReportStatus.pending &&
      !reports.hasVotedOn(report.id) &&
      auth.canVoteOn(
        reporterId: report.reporterId,
        reportWard: report.ward,
        reportLga: report.lga,
      );

  Future<void> _vote({required bool confirm}) async {
    final reports = context.read<ReportsStatusProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    String? comment;
    if (!confirm) {
      comment = await showDisputeCommentDialog(context);
      if (comment == null || !mounted) return;
    }
    setState(() => _submitting = true);
    try {
      if (confirm) {
        await reports.verifyReport(widget.report.id);
      } else {
        await reports.disputeReport(widget.report.id, comment: comment);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            confirm ? l10n.voteConfirmedThanks : l10n.voteDisputeRecorded,
          ),
          backgroundColor: confirm ? AppColors.successGreen : Colors.orange,
        ),
      );
      widget.onVoted?.call();
    } on VerificationRefusedException catch (e) {
      if (e.noLongerPending && mounted) {
        setState(() => _noLongerPending = true);
      }
      messenger.showSnackBar(
        SnackBar(content: Text(e.message(l10n)), backgroundColor: Colors.red),
      );
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ErrorHandler.handleError(e, l10n, context: 'Verification'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final reports = context.watch<ReportsStatusProvider>();
    if (_noLongerPending || !canVote(auth, reports, widget.report)) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.voteQuestion,
            style: GoogleFonts.lexend(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _submitting ? null : () => _vote(confirm: false),
                  icon: const Icon(Icons.close, color: Colors.red),
                  label: Text(
                    context.l10n.voteDispute,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : () => _vote(confirm: true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.successGreen,
                    foregroundColor: Colors.white,
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(context.l10n.voteConfirm),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
