import 'package:flutter/material.dart';

/// One row of an admin popup menu: an icon, then its label.
///
/// These labels used to carry the icon as an emoji inside the translated
/// string ("✅ Approve", "🚫 Disable user"). That put a glyph the app cannot
/// control in every translator's hands, and it renders as an empty box on any
/// device without an emoji font — which is exactly where the colour cue was
/// doing the work. Drawing an [Icon] keeps the cue, keeps the strings
/// translatable, and lets the icon be tinted with the action's colour.
///
/// The icon is marked [ExcludeSemantics] because the label already says what
/// the action is; announcing both would repeat it.
class AdminMenuEntry extends StatelessWidget {
  const AdminMenuEntry({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;

  /// Tints both the icon and the label, for destructive or restorative
  /// actions. Defaults to the menu's normal foreground colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 20, color: color)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}
