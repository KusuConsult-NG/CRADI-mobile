import 'package:climate_app/core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Severity shown as a coloured dot next to its written label.
///
/// This replaces the emoji markers (🔴🟠🟡🟢) the lists used to prefix the
/// label with. Those carried the level in the colour alone, and rendered as
/// a tofu box on any device without an emoji font. The dot is drawn, not
/// typed, and the level is always spelled out beside it; screen readers get
/// the level through [AppLocalizations.a11ySeverityLabel], as elsewhere in
/// the app.
class SeverityMarker extends StatelessWidget {
  const SeverityMarker({
    super.key,
    required this.label,
    required this.color,
    this.textStyle,
  });

  /// The written severity, already localised (e.g. "Low").
  final String label;

  /// The colour for this level — a second cue, never the only one.
  final Color color;

  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.a11ySeverityLabel(label),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style:
                  textStyle ??
                  GoogleFonts.lexend(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
