import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// Asks senior staff for the (required) reason of a rejection; it is shown
/// to the reporter. Returns the trimmed reason, or null when cancelled.
Future<String?> showRejectReasonDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _RejectReasonDialog(),
    );

/// Status actions a status manager may apply to a report in [status]
/// (mirrors `guard_report_update` / `reopen_report`): approve a verified
/// report, reject a pending or verified one, reopen anything not pending.
@visibleForTesting
({bool approve, bool reject, bool reopen}) staffActionsFor(
  ReportStatus status,
) => (
  approve: status == ReportStatus.verified,
  reject: status == ReportStatus.pending || status == ReportStatus.verified,
  reopen: status != ReportStatus.pending,
);

/// Approve / reject / reopen buttons for senior staff on the report screen
/// (e.g. opened from a push). Shown only when
/// [AuthProvider.canManageReportStatus] allows it; [onChanged] runs after a
/// successful action so the screen can re-fetch the report.
class ReportStaffActions extends StatefulWidget {
  const ReportStaffActions({
    super.key,
    required this.report,
    required this.onChanged,
  });

  final VerificationReport report;
  final Future<void> Function() onChanged;

  @override
  State<ReportStaffActions> createState() => _ReportStaffActionsState();
}

class _ReportStaffActionsState extends State<ReportStaffActions> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(ReportsStatusProvider p) action,
    String success,
  ) async {
    final provider = context.read<ReportsStatusProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await action(provider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(success),
          backgroundColor: AppColors.successGreen,
        ),
      );
      await widget.onChanged();
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(reportActionErrorMessage(e, l10n)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reason = await showRejectReasonDialog(context);
    if (reason == null || !mounted) return;
    await _run(
      (p) => p.staffRejectReport(widget.report.id, reason: reason),
      context.l10n.staffRejected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final report = widget.report;
    if (!auth.canManageReportStatus(reporterId: report.reporterId)) {
      return const SizedBox.shrink();
    }
    final actions = staffActionsFor(report.status);
    if (!actions.approve && !actions.reject && !actions.reopen) {
      return const SizedBox.shrink();
    }
    final id = report.id;
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
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.staffActionsTitle,
                  style: GoogleFonts.lexend(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (actions.approve)
                ElevatedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          (p) => p.approveReport(id),
                          context.l10n.staffApproved,
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(context.l10n.staffApprove),
                ),
              if (actions.reject)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _reject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(context.l10n.reject),
                ),
              if (actions.reopen)
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          (p) => p.moveBackToPending(id),
                          context.l10n.staffReopened,
                        ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(context.l10n.reopen),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        context.l10n.staffRejectTitle,
        style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        maxLength: 500,
        onChanged: (_) {
          if (_showError) setState(() => _showError = false);
        },
        decoration: InputDecoration(
          labelText: context.l10n.staffRejectReasonLabel,
          hintText: context.l10n.staffRejectReasonHint,
          border: const OutlineInputBorder(),
          errorText: _showError ? context.l10n.staffRejectReasonRequired : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(
            context.l10n.reject,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}
