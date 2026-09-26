import 'package:climate_app/core/l10n/l10n.dart';

class EmergencyContact {
  final String id;
  final String name;
  final String role;
  final String phone;
  final String? organization;
  final String? lga;
  final String
  category; // 'coordinator', 'emergency', 'agri-extension', 'other'
  final bool isAvailable;

  EmergencyContact({
    required this.id,
    required this.name,
    required this.role,
    required this.phone,
    this.organization,
    this.lga,
    required this.category,
    this.isAvailable = true,
  });

  factory EmergencyContact.fromMap(Map<String, dynamic> data, String id) {
    return EmergencyContact(
      id: id,
      name: data['name'] as String? ?? '',
      role: data['role'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      organization: data['organization'] as String?,
      lga: data['lga'] as String?,
      category: data['category'] as String? ?? 'other',
      isAvailable: data['isAvailable'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'role': role,
      'phone': phone,
      // Always sent (null clears the column on update).
      'organization': organization,
      'lga': lga,
      'category': category,
      'isAvailable': isAvailable,
    };
  }

  /// Validates a contact name (required, at most 100 characters).
  static String? validateName(String? value, AppLocalizations l10n) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return l10n.contactsNameRequired;
    if (v.length > 100) return l10n.contactsNameTooLong;
    return null;
  }

  /// Validates a contact phone number: required; digits with an optional
  /// leading '+', spaces, dashes and brackets allowed. Short codes (e.g.
  /// 112) are accepted, as are local and international numbers.
  static String? validatePhone(String? value, AppLocalizations l10n) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return l10n.validatorPhoneRequired;
    if (!RegExp(r'^\+?[\d\s\-()]+$').hasMatch(v)) {
      return l10n.contactsPhoneDigitsOnly;
    }
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 3 || digits.length > 15) {
      return l10n.contactsPhoneInvalid;
    }
    return null;
  }
}
