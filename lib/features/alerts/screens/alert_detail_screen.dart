import 'package:climate_app/core/constants/hazards.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/utils/error_handler.dart';
import 'package:climate_app/core/services/supabase_service.dart';

import 'package:climate_app/features/alerts/screens/alert_severity.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:climate_app/features/verification/providers/reports_status_provider.dart';
import 'package:climate_app/features/verification/models/verification_report_model.dart';
import 'package:climate_app/features/verification/widgets/dispute_comment_dialog.dart';
import 'package:climate_app/features/verification/widgets/verification_request_badge.dart';

import 'package:climate_app/features/alerts/providers/alerts_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// Detail view for an alert.
///
/// Accepts either a report-derived map from the alerts list (title, type,
/// severity, location, time, status, description, reportId, reporterId,
/// ward, color, icon) or an `alerts` row created by staff (title, message,
/// severity, targetLga, reportId?, isActive, createdAt). Every field is
/// optional.
class AlertDetailScreen extends StatefulWidget {
  final Map<String, dynamic> alert;

  const AlertDetailScreen({super.key, required this.alert});

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;
  bool _hasVerified = false;

  @override
  void initState() {
    super.initState();
    // Votes of the signed-in user, to hide the vote actions on a report
    // already voted on. Re-read: a reopen elsewhere may have cleared them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ReportsStatusProvider>().loadMyVotes(force: true);
      }
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// Non-empty string value of the first present key, else null.
  String? _str(List<String> keys) {
    for (final k in keys) {
      final v = widget.alert[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  String? get _reportId => _str(['reportId', 'report_id']);

  String get _title => _str(['title']) ?? context.l10n.alertDetailDefaultTitle;

  String? get _severity => _str(['severity']);

  String get _location =>
      _str(['location']) ??
      AlertsProvider.targetLabel(widget.alert) ??
      _str(['targetLga', 'target_lga']) ??
      context.l10n.alertDetailNotSpecified;

  String get _time {
    final t = _str(['time']);
    if (t != null) return t;
    final created = parseTimestamp(
      widget.alert['createdAt'] ?? widget.alert['created_at'],
    );
    return created == null
        ? context.l10n.timeJustNow
        : localizedDateFormat(
            context,
            'MMM d, yyyy • h:mm a',
          ).format(created.toLocal());
  }

  /// Stored status ('pending', 'approved', …) or 'active' / 'inactive'
  /// for staff alerts.
  String get _status {
    final s = _str(['status']);
    if (s != null) return s;
    final active = widget.alert['isActive'] ?? widget.alert['is_active'];
    return active == false ? 'inactive' : 'active';
  }

  /// Display text for [_status].
  String _statusLabel(String status) {
    final l10n = context.l10n;
    switch (status.toLowerCase()) {
      case 'active':
        return l10n.alertStatusActive;
      case 'inactive':
        return l10n.alertStatusInactive;
    }
    for (final s in ReportStatus.values) {
      if (s.name == status.toLowerCase()) return s.label(l10n);
    }
    return status;
  }

  /// Whether the alert is a report sent as a verification request.
  bool get _isVerificationRequest =>
      _str(['reportType']) == VerificationReport.verificationRequestType;

  /// Hazard of a report-derived alert (null for staff alerts).
  Hazard? get _hazard => Hazard.tryParse(_str(['type', 'hazardType']));

  /// Hazard colour for reports (same as the list card), else the colour
  /// handed over by the caller, else by severity (staff alerts).
  Color get _severityColor {
    final hazard = _hazard;
    if (hazard != null) return hazard.color;
    final c = widget.alert['color'];
    if (c is Color) return c;
    return alertSeverityColor(_severity);
  }

  IconData get _icon {
    final hazard = _hazard;
    if (hazard != null) return hazard.icon;
    final i = widget.alert['icon'];
    return i is IconData ? i : alertSeverityIcon(_severity);
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/alerts');
    }
  }

  Future<void> _submitVerification(bool isConfirmed) async {
    if (_isSubmitting || _hasVerified) return;

    // A dispute must say what is wrong with the report.
    var comment = _commentController.text.trim();
    if (!isConfirmed && comment.isEmpty) {
      final entered = await showDisputeCommentDialog(context);
      if (entered == null || !mounted) return;
      comment = entered;
      _commentController.text = entered;
    }

    setState(() => _isSubmitting = true);

    final reports = context.read<ReportsStatusProvider>();
    try {
      final reportId = _reportId;
      if (reportId == null || reportId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.alertDetailReportLoadError),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Through the provider so the voted-on cache and the lists refresh.
      if (isConfirmed) {
        await reports.verifyReport(
          reportId,
          comment: comment.isEmpty ? null : comment,
        );
      } else {
        await reports.disputeReport(reportId, comment: comment);
      }

      if (!mounted) return;
      setState(() => _hasVerified = true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isConfirmed
                ? context.l10n.verifyConfirmedMessage
                : context.l10n.verifyDisputedMessage,
          ),
          backgroundColor: isConfirmed ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );

      // Wait a bit then go back
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _close();
      });
    } on VerificationRefusedException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message(context.l10n)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorHandler.handleError(
                e,
                context.l10n,
                context: 'Alert Verification',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final severityColor = _severityColor;
    final status = _status;
    final auth = context.watch<AuthProvider>();
    final reports = context.watch<ReportsStatusProvider>();
    final reportId = _reportId;
    // Peer verification only applies to a report-backed alert the user may
    // vote on (mirrors the verifications_insert policy) and has not voted
    // on yet.
    final isPendingVerification =
        status.toLowerCase() == 'pending' &&
        reportId != null &&
        !reports.hasVotedOn(reportId) &&
        auth.canVoteOn(
          reporterId: _str(['reporterId']),
          reportWard: _str(['ward']),
          reportLga: _str(['lga']),
        );
    final description = _str(['description', 'message']);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.l10n.back,
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: _close,
        ),
        title: Text(
          context.l10n.alertDetailTitle,
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: severityColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: ExcludeSemantics(
                          child: Icon(_icon, color: severityColor, size: 32),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _title,
                              style: GoogleFonts.lexend(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Severity is also signalled by the icon and the
                            // colour, neither of which a screen reader can
                            // convey, so the text node carries the meaning.
                            Semantics(
                              label: context.l10n.a11ySeverityLabel(
                                alertSeverityLabel(_severity, context.l10n),
                              ),
                              excludeSemantics: true,
                              child: Text(
                                alertSeverityLabel(_severity, context.l10n),
                                style: GoogleFonts.lexend(
                                  fontSize: 14,
                                  color: severityColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (_isVerificationRequest) ...[
                              const SizedBox(height: 6),
                              const VerificationRequestBadge(),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  _buildInfoRow(
                    Icons.location_on,
                    context.l10n.locationLabel,
                    _location,
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    Icons.schedule,
                    context.l10n.alertDetailReportedTime,
                    _time,
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(
                    Icons.info_outline,
                    context.l10n.alertDetailStatus,
                    _statusLabel(status),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Text(
              context.l10n.descriptionLabel,
              style: GoogleFonts.lexend(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              description ?? context.l10n.alertDetailNoDescription,
              style: GoogleFonts.lexend(
                fontSize: 15,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),

            const SizedBox(height: 24),

            Text(
              context.l10n.alertDetailRecommendedActions,
              style: GoogleFonts.lexend(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _buildActionItem(context.l10n.alertDetailAction1),
            _buildActionItem(context.l10n.alertDetailAction2),
            _buildActionItem(context.l10n.alertDetailAction3),
            _buildActionItem(context.l10n.alertDetailAction4),

            // Verification Section (only show if pending)
            if (isPendingVerification && !_hasVerified) ...[
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.verified_user,
                          color: Colors.blue.shade700,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.l10n.alertDetailPeerVerificationTitle,
                            style: GoogleFonts.lexend(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.alertDetailPeerVerificationBody,
                      style: GoogleFonts.lexend(
                        fontSize: 14,
                        color: Colors.blue.shade700,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Optional Comment Field
                    TextField(
                      controller: _commentController,
                      decoration: InputDecoration(
                        labelText: context.l10n.alertDetailCommentLabel,
                        hintText: context.l10n.alertDetailCommentHint,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.blue.shade400),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      maxLines: 3,
                      maxLength: 200,
                      enabled: !_isSubmitting,
                    ),
                    const SizedBox(height: 16),

                    // Verification Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.check_circle, size: 20),
                            label: Text(
                              _isSubmitting
                                  ? context.l10n.commonSubmitting
                                  : context.l10n.voteConfirm,
                              style: GoogleFonts.lexend(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            onPressed: _isSubmitting
                                ? null
                                : () => _submitVerification(true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.red,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.cancel, size: 20),
                            label: Text(
                              _isSubmitting
                                  ? context.l10n.commonSubmitting
                                  : context.l10n.voteDecline,
                              style: GoogleFonts.lexend(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(
                                color: Colors.red,
                                width: 2,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _isSubmitting
                                ? null
                                : () => _submitVerification(false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Show confirmation message if already verified
            if (_hasVerified) ...[
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green.shade700,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.alertDetailVerificationSubmitted,
                            style: GoogleFonts.lexend(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.l10n.alertDetailThanks,
                            style: GoogleFonts.lexend(
                              fontSize: 14,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),

      // Bottom Action Button (Dismiss or Back)
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _close,
              style: ElevatedButton.styleFrom(
                backgroundColor: _hasVerified
                    ? Colors.grey.shade600
                    : AppColors.primaryRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: Text(
                _hasVerified
                    ? context.l10n.alertDetailGoBack
                    : context.l10n.alertDetailDismiss,
                style: GoogleFonts.lexend(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade400),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.lexend(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.lexend(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: GoogleFonts.lexend(fontSize: 14, color: AppColors.textSecondary),
      ),
    );
  }
}
