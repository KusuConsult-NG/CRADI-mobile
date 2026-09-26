import 'package:climate_app/core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Small "Verification request" pill shown on reports whose row kind is
/// `verification_request` (see [VerificationReport.isVerificationRequest]).
class VerificationRequestBadge extends StatelessWidget {
  const VerificationRequestBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Colors.indigo.shade600;
    return Container(
      key: const ValueKey('verification-request-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fact_check_outlined, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              context.l10n.verificationRequestBadge,
              style: GoogleFonts.lexend(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
