import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// The hazard types a report can have.
///
/// [storedName] is the exact value written to `reports.hazard_type` by the
/// reporting flow (see HazardSelectionScreen). Older rows and other entry
/// points used different spellings; those are listed in [aliases] so every
/// screen resolves them to the same metadata.
enum Hazard {
  flooding(
    storedName: 'Flooding',
    label: 'Flooding',
    title: 'Flood Alert',
    icon: Icons.flood,
    iconKey: 'flood',
    color: AppColors.hazardFlood,
    aliases: ['flood', 'floods', 'flash flood'],
  ),
  extremeTemperatures(
    storedName: 'Extreme Temperatures',
    label: 'Extreme Temperatures',
    title: 'Temperature Extreme',
    icon: Icons.thermostat,
    iconKey: 'thermostat',
    color: AppColors.hazardTemp,
    aliases: [
      'extreme temperature',
      'extreme heat',
      'heatwave',
      'heat wave',
      'temp',
    ],
  ),
  drought(
    storedName: 'Drought',
    label: 'Drought',
    title: 'Drought Warning',
    icon: Icons.wb_sunny_rounded,
    iconKey: 'sunny',
    color: AppColors.hazardDrought,
    aliases: [],
  ),
  windstorms(
    storedName: 'Windstorms',
    label: 'Windstorms',
    title: 'High Wind Alert',
    icon: Icons.air,
    iconKey: 'air',
    color: AppColors.hazardWind,
    aliases: ['windstorm', 'high winds', 'high wind', 'wind', 'storm'],
  ),
  wildfires(
    storedName: 'Wildfires',
    label: 'Wildfires',
    title: 'Wildfire Report',
    icon: Icons.local_fire_department,
    iconKey: 'fire',
    color: AppColors.hazardFire,
    aliases: ['wildfire', 'fire', 'bush fire', 'bushfire'],
  ),
  erosion(
    storedName: 'Erosion',
    label: 'Erosion',
    title: 'Erosion Report',
    icon: Icons.landslide,
    iconKey: 'landslide',
    color: AppColors.hazardErosion,
    aliases: ['gully erosion', 'landslide'],
  ),
  pestOutbreak(
    storedName: 'Pest Outbreak',
    label: 'Pest Outbreak',
    title: 'Pest Outbreak',
    icon: Icons.pest_control,
    iconKey: 'pest',
    color: AppColors.hazardPest,
    aliases: ['pest', 'pests', 'pest/disease'],
  ),
  cropDisease(
    storedName: 'Crop Disease',
    label: 'Crop Disease',
    title: 'Crop Disease',
    icon: Icons.coronavirus_rounded,
    iconKey: 'disease',
    color: Colors.green,
    aliases: ['crop diseases', 'disease'],
  ),
  conflict(
    storedName: 'Conflict',
    label: 'Conflict',
    title: 'Conflict Report',
    icon: Icons.warning_amber_rounded,
    iconKey: 'conflict',
    color: AppColors.primaryRed,
    aliases: ['conflicts', 'violence'],
  );

  const Hazard({
    required this.storedName,
    required this.label,
    required this.title,
    required this.icon,
    required this.iconKey,
    required this.color,
    required this.aliases,
  });

  /// Value stored in `reports.hazard_type`.
  final String storedName;

  /// Short display name.
  final String label;

  /// Headline used on report cards.
  final String title;

  final IconData icon;

  /// Serialisable icon id (kept on [VerificationReport.iconName]).
  final String iconKey;

  final Color color;

  /// Lower-case legacy spellings that resolve to this hazard.
  final List<String> aliases;

  /// Resolves a stored / legacy hazard name. Returns null when unknown.
  static Hazard? tryParse(Object? raw) {
    if (raw == null) return null;
    final value = raw.toString().trim().toLowerCase();
    if (value.isEmpty) return null;
    for (final h in Hazard.values) {
      if (h.storedName.toLowerCase() == value ||
          h.name.toLowerCase() == value ||
          h.aliases.contains(value)) {
        return h;
      }
    }
    return null;
  }

  /// Canonical stored name for [raw], or [raw] itself when unknown.
  static String canonicalName(Object? raw) =>
      tryParse(raw)?.storedName ?? (raw?.toString() ?? '');

  static String labelFor(Object? raw) =>
      tryParse(raw)?.label ?? _fallbackText(raw, 'Unknown Hazard');

  static String titleFor(Object? raw) =>
      tryParse(raw)?.title ?? _fallbackText(raw, 'Unknown Hazard');

  static IconData iconFor(Object? raw) =>
      tryParse(raw)?.icon ?? Icons.warning_amber_rounded;

  static Color colorFor(Object? raw) => tryParse(raw)?.color ?? Colors.orange;

  static String iconKeyFor(Object? raw) => tryParse(raw)?.iconKey ?? 'warning';

  /// Icon for a serialised [iconKey] (also accepts legacy material names
  /// such as 'water' or 'local_fire_department').
  static IconData iconForKey(String? key) {
    for (final h in Hazard.values) {
      if (h.iconKey == key) return h.icon;
    }
    switch (key) {
      case 'water':
        return Icons.flood;
      case 'water_drop':
      case 'wb_sunny':
        return Icons.wb_sunny_rounded;
      case 'local_fire_department':
        return Icons.local_fire_department;
      case 'pest_control':
        return Icons.pest_control;
      case 'shield':
        return Icons.warning_amber_rounded;
      case 'landscape':
        return Icons.landslide;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  static String _fallbackText(Object? raw, String fallback) {
    final s = raw?.toString().trim() ?? '';
    return s.isEmpty ? fallback : s;
  }
}

/// Colour names for severities (serialised on [VerificationReport.iconColor])
/// and their display colours. High and medium are deliberately distinct.
class SeverityColors {
  SeverityColors._();

  /// Colour name for a canonical severity ('low' | 'medium' | 'high' |
  /// 'critical'). Unknown values map to 'grey'.
  static String nameFor(String? canonicalSeverity) {
    switch (canonicalSeverity) {
      case 'low':
        return 'green';
      case 'medium':
        return 'amber';
      case 'high':
        return 'orange';
      case 'critical':
        return 'red';
      default:
        return 'grey';
    }
  }

  /// Display colour for a colour name produced by [nameFor] (also accepts
  /// 'blue', used by older cached data).
  static Color fromName(String? name) {
    switch (name) {
      case 'green':
        return AppColors.successGreen;
      case 'amber':
        return Colors.amber.shade700;
      case 'orange':
        return Colors.deepOrange;
      case 'red':
        return AppColors.errorRed;
      case 'blue':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
