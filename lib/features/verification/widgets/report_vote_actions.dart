import 'dart:async';

import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

/// Confirm / Dispute peer-vote buttons for a pending report, shown only
/// when the signed-in user may vote on it (same rules as the database) and
/// has not voted yet. Used on the report screen that a
/// `verification_request` push opens.
class ReportVoteActions extends StatefulWidget {
  const ReportVoteActions({super.key, required this.report});

  final VerificationReport report;

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

  Future<String?> _askDisputeComment() => showDialog<String>(
    context: context,
    builder: (_) => const _DisputeDialog(),
  );

  Future<void> _vote({required bool confirm}) async {
    final reports = context.read<ReportsStatusProvider>();
    final messenger = ScaffoldMessenger.of(context);
    String? comment;
    if (!confirm) {
      comment = await _askDisputeComment();
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
            confirm
                ? 'Report confirmed. Thank you!'
                : 'Dispute recorded. Staff will review the report.',
          ),
          backgroundColor: confirm ? AppColors.successGreen : Colors.orange,
        ),
      );
    } on VerificationRefusedException catch (e) {
      if (e.noLongerPending && mounted) {
        setState(() => _noLongerPending = true);
      }
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(ErrorHandler.handleError(e, context: 'Verification')),
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
            'Can you verify this report?',
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
                  label: const Text(
                    'Dispute',
                    style: TextStyle(color: Colors.red),
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
                  label: const Text('Confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for the (required) dispute comment. Owns its text controller so it
/// is disposed only once the dialog route is gone.
class _DisputeDialog extends StatefulWidget {
  const _DisputeDialog();

  @override
  State<_DisputeDialog> createState() => _DisputeDialogState();
}

class _DisputeDialogState extends State<_DisputeDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Dispute report?',
        style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        maxLength: 500,
        decoration: const InputDecoration(
          labelText: 'What is wrong with this report? (required)',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.isNotEmpty) Navigator.pop(context, text);
          },
          child: const Text('Dispute', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}
