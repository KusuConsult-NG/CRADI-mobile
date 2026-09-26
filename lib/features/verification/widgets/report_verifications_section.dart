import 'package:climate_app/core/services/peer_verification_service.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/auth/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/l10n/l10n.dart';

/// Peer confirmations and disputes (with their comments) on a report, for
/// the roles that may read them ([AuthProvider.verificationReaderRoles]).
/// Changing [refreshToken] reloads the votes (e.g. after a staff action).
class ReportVerificationsSection extends StatefulWidget {
  const ReportVerificationsSection({
    super.key,
    required this.reportId,
    this.refreshToken = 0,
    this.loader,
  });

  final String reportId;
  final int refreshToken;

  /// Loads the votes; defaults to [PeerVerificationService.getVerifications]
  /// (injectable for tests).
  final Future<List<ReportVerification>> Function(String reportId)? loader;

  @override
  State<ReportVerificationsSection> createState() =>
      _ReportVerificationsSectionState();
}

class _ReportVerificationsSectionState
    extends State<ReportVerificationsSection> {
  Future<List<ReportVerification>>? _future;

  bool _canRead(AuthProvider auth) =>
      AuthProvider.verificationReaderRoles.contains(auth.userRole);

  @override
  void initState() {
    super.initState();
    if (_canRead(context.read<AuthProvider>())) _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant ReportVerificationsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reportId != widget.reportId ||
        oldWidget.refreshToken != widget.refreshToken) {
      if (_canRead(context.read<AuthProvider>())) _load();
    }
  }

  Future<List<ReportVerification>> _fetch() {
    final loader = widget.loader ?? PeerVerificationService().getVerifications;
    return loader(widget.reportId);
  }

  void _load() => setState(() => _future = _fetch());

  @override
  Widget build(BuildContext context) {
    if (!_canRead(context.watch<AuthProvider>())) {
      return const SizedBox.shrink();
    }
    if (_future == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _future == null) _load();
      });
    }
    return FutureBuilder<List<ReportVerification>>(
      future: _future,
      builder: (context, snap) {
        final Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        } else if (snap.hasError) {
          body = Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.verificationsLoadError,
                  style: GoogleFonts.lexend(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(onPressed: _load, child: Text(context.l10n.retry)),
            ],
          );
        } else {
          body = _buildList(snap.data ?? const []);
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
                context.l10n.verificationsTitle,
                style: GoogleFonts.lexend(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              body,
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(List<ReportVerification> votes) {
    final confirmations = votes.where((v) => v.isConfirmed).length;
    final disputes = votes.length - confirmations;
    final uid = context.read<AuthProvider>().currentUser?.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.verificationsSummary(confirmations, disputes),
          style: GoogleFonts.lexend(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: disputes > 0
                ? Colors.orange.shade800
                : AppColors.textPrimary,
          ),
        ),
        if (votes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              context.l10n.verificationsNone,
              style: GoogleFonts.lexend(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        for (final v in votes) _buildVote(v, isMine: v.verifierId == uid),
      ],
    );
  }

  Widget _buildVote(ReportVerification v, {required bool isMine}) {
    final color = v.isConfirmed ? AppColors.successGreen : Colors.orange;
    final l10n = context.l10n;
    final who = isMine
        ? l10n.verificationsYou
        : (v.verifierName ?? l10n.verificationsPeerVerifier);
    final kind = v.isConfirmed ? 'confirmed' : 'disputed';
    final line = v.submittedAt == null
        ? l10n.verificationsVoteBy(kind, who)
        : l10n.verificationsVoteByAt(
            kind,
            who,
            localizedDateFormat(
              context,
              'MMM d, h:mm a',
            ).format(v.submittedAt!),
          );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            v.isConfirmed ? Icons.check_circle : Icons.report_problem,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line,
                  style: GoogleFonts.lexend(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (v.comment.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      v.comment,
                      style: GoogleFonts.lexend(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
