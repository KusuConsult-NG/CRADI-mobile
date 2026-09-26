import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A knowledge-base category. [hazardType] is the value stored in
/// `knowledge_base.hazard_type`; [label] is shown to users and stored in
/// `knowledge_base.category`.
class KnowledgeCategory {
  const KnowledgeCategory({
    required this.label,
    required this.hazardType,
    required this.icon,
    required this.color,
    this.aliases = const [],
  });

  final String label;
  final String hazardType;
  final IconData icon;
  final Color color;

  /// Other spellings found in older rows / the bundled fallback guides.
  final List<String> aliases;

  bool matches(Object? value) {
    final v = value?.toString().trim().toLowerCase() ?? '';
    if (v.isEmpty) return false;
    return v == hazardType || v == label.toLowerCase() || aliases.contains(v);
  }
}

/// Pseudo-category meaning "no filter".
const String allKnowledgeCategories = 'All';

/// The single list of knowledge-base categories, shared by the admin editor
/// (what is written) and the reader screens (what is filtered on).
const List<KnowledgeCategory> knowledgeCategories = [
  KnowledgeCategory(
    label: 'Flood',
    hazardType: 'flood',
    icon: Icons.water,
    color: Colors.blue,
    aliases: ['floods', 'flooding'],
  ),
  KnowledgeCategory(
    label: 'Fire',
    hazardType: 'fire',
    icon: Icons.local_fire_department,
    color: Colors.red,
    aliases: ['wildfire', 'wildfires'],
  ),
  KnowledgeCategory(
    label: 'Erosion',
    hazardType: 'erosion',
    icon: Icons.terrain,
    color: Colors.brown,
  ),
  KnowledgeCategory(
    label: 'Storm',
    hazardType: 'storm',
    icon: Icons.thunderstorm,
    color: Colors.indigo,
    aliases: ['storms', 'windstorm', 'windstorms'],
  ),
  KnowledgeCategory(
    label: 'Extreme Heat',
    hazardType: 'extreme_heat',
    icon: Icons.thermostat,
    color: Colors.deepOrange,
    aliases: ['extreme heat', 'heat', 'heatwave', 'drought'],
  ),
  KnowledgeCategory(
    label: 'Earthquake',
    hazardType: 'earthquake',
    icon: Icons.vibration,
    color: Colors.orange,
  ),
  KnowledgeCategory(
    label: 'Disease',
    hazardType: 'disease',
    icon: Icons.coronavirus_outlined,
    color: Colors.green,
    aliases: ['epidemic', 'pest/disease'],
  ),
  KnowledgeCategory(
    label: 'Conflict',
    hazardType: 'conflict',
    icon: Icons.shield_outlined,
    color: Color(0xFFB71C1C),
  ),
  KnowledgeCategory(
    label: 'Accident',
    hazardType: 'accident',
    icon: Icons.car_crash_outlined,
    color: Colors.amber,
  ),
  KnowledgeCategory(
    label: 'Safety',
    hazardType: 'safety',
    icon: Icons.health_and_safety_outlined,
    color: Colors.purple,
  ),
  KnowledgeCategory(
    label: 'General',
    hazardType: 'general',
    icon: Icons.menu_book_outlined,
    color: Colors.teal,
  ),
];

/// Filter labels for reader screens: 'All' followed by every category.
List<String> get knowledgeCategoryFilters => [
  allKnowledgeCategories,
  for (final c in knowledgeCategories) c.label,
];

/// The category matching a label, hazard type or alias, or null.
KnowledgeCategory? knowledgeCategoryFor(Object? value) {
  for (final c in knowledgeCategories) {
    if (c.matches(value)) return c;
  }
  return null;
}

/// Whether [guide] belongs to [category] (a label or hazard type). 'All'
/// (or null) matches everything.
bool guideMatchesCategory(Map<String, dynamic> guide, String? category) {
  if (category == null || category == allKnowledgeCategories) return true;
  final target = knowledgeCategoryFor(category);
  if (target == null) {
    final c = category.toLowerCase();
    return guide['hazardType']?.toString().toLowerCase() == c ||
        guide['category']?.toString().toLowerCase() == c;
  }
  final byHazard = knowledgeCategoryFor(guide['hazardType']);
  if (byHazard != null) return byHazard.hazardType == target.hazardType;
  return target.matches(guide['category']);
}

/// Formats a knowledge-base / news date for display in local time, e.g.
/// '3 Mar 2026'. Accepts a [DateTime], an ISO-8601 string or epoch
/// milliseconds; any other non-empty text (e.g. 'March 2026') is shown as is.
/// Returns null when there is nothing to show.
String? formatKnowledgeDate(Object? raw) {
  DateTime? date;
  if (raw is DateTime) {
    date = raw;
  } else if (raw is int) {
    date = DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
  } else if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    date = DateTime.tryParse(text);
    if (date == null) return text;
  }
  if (date == null) return null;
  return DateFormat('d MMM yyyy').format(date.toLocal());
}
