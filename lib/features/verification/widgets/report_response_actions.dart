import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

/// Where the response to a report has got to, and — for an Early Responder
/// — the control that moves it on.
///
/// Deliberately separate from [ReportStaffActions]: that decides whether a
/// report is *true*, this says what is being *done* about it, and the
/// client's permission matrix (4.1) gives the two to different roles. A
/// responder sees this on a report it has no power to approve.
///
/// Shown read-only to everyone else, because knowing a team is already on
/// the way is useful to the reporter and to the staff reviewing it.
class ReportResponseActions extends StatefulWidget {
  const ReportResponseActions({
    super.key,
    required this.report,
    required this.onChanged,
  });

  final VerificationReport report;
  final Future<void> Function() onChanged;

  @override
  State<ReportResponseActions> createState() => _ReportResponseActionsState();
}

class _ReportResponseActionsState extends State<ReportResponseActions> {
  bool _busy = false;

  Future<void> _set(ResponseStatus status) async {
    if (status == widget.report.responseStatus) return;
    final provider = context.read<ReportsStatusProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await provider.updateResponseStatus(widget.report.id, status);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.responseStatusUpdated),
          backgroundColor: AppColors.successGreen,
        ),
      );
      await widget.onChanged();
      // `Object`, not `Exception`: an `Error` here would otherwise leave the
      // chips disabled with nothing said, which is the defect this codebase
      // has already been bitten by twice.
    } on Object catch (e) {
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final report = widget.report;
    final canEdit = auth.canUpdateResponseStatus(
      reportIsValidated: validatedReportStatuses.contains(report.status),
    );

    // Nothing has happened yet and this user cannot make it happen: an
    // "Awaiting response" card on every report would be noise.
    if (!canEdit && report.responseStatus == ResponseStatus.awaiting) {
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
            context.l10n.responseStatusTitle,
            style: GoogleFonts.lexend(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (!canEdit)
            Text(
              report.responseStatus.label(context.l10n),
              style: GoogleFonts.lexend(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final status in ResponseStatus.values)
                  ChoiceChip(
                    label: Text(status.label(context.l10n)),
                    selected: report.responseStatus == status,
                    // A disabled chip during the write, rather than a
                    // spinner over the card: the current value stays
                    // readable while it is being changed.
                    onSelected: _busy ? null : (_) => _set(status),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
