import 'package:climate_app/core/design/animated_card.dart';
import 'package:climate_app/core/design/typography.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/widgets/word_safe_label.dart';
import 'package:flutter/material.dart';

/// One of the three counters at the top of the dashboard (active / pending /
/// approved).
///
/// Three of these share the screen width, so at 320 px each is about 90 px
/// wide. The label is laid out with [WordSafeLabel] so a single long word —
/// "Pending", or its longer translation — shrinks or wraps between words
/// instead of being broken in half ("Pendin/g").
class DashboardStatCard extends StatelessWidget {
  const DashboardStatCard({
    super.key,
    required this.count,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String count;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedCard(
      borderRadius: 20,
      backgroundColor: Colors.white,
      padding: const EdgeInsets.all(18),
      shadows: [
        BoxShadow(
          color: color.withValues(alpha: 0.15),
          blurRadius: 25,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 15,
          offset: const Offset(0, 6),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // At 320 px each card is about 90 px wide — narrower than the
          // hazard tile and the arrow together — so the pair is scaled down
          // to fit rather than spilling over the card's edge.
          LayoutBuilder(
            builder: (context, constraints) => FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : 0,
                ),
                child: IntrinsicWidth(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              color.withValues(alpha: 0.2),
                              color.withValues(alpha: 0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: color.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Icon(icon, color: color, size: 22),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward,
                          color: color,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          WordSafeLabel(
            count,
            maxLines: 1,
            style: PremiumTypography.heading2(
              context,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          WordSafeLabel(label, style: PremiumTypography.subtitle(context)),
        ],
      ),
    );
  }
}
