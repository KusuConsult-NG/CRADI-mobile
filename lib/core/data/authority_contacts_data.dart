/// Authority Contacts Database for CRADI Mobile
///
/// Pre-loaded contacts for emergency services and disaster management
/// authorities across Benue, Nasarawa, and Plateau states
///
/// Data sources:
/// - State Emergency Management Agencies (SEMA)
/// - Nigeria Police Force
/// - Agricultural Extension Officers
/// - Local Government contacts
///
/// Last Updated: 2025-12-30
/// Coverage: 53 LGAs across 3 states

library;

import 'mvp_locations_data.dart';

class AuthorityContact {
  final String name;
  final String role;
  final String phone;
  final String? email;
  final String? office;
  final String lga;
  final String state;
  final String category; // 'SEMA', 'Police', 'Extension', 'LGA'
  final int priority; // 1 = critical, 2 = high, 3 = medium

  const AuthorityContact({
    required this.name,
    required this.role,
    required this.phone,
    this.email,
    this.office,
    required this.lga,
    required this.state,
    required this.category,
    this.priority = 2,
  });
}

class AuthorityContactsData {
  // ==================== STATE-LEVEL AUTHORITIES ====================

  /// State Emergency Management Agency (SEMA) Directors
  static const List<AuthorityContact> _stateAuthorities = [
    // Benue State
    AuthorityContact(
      name: 'Benue SEMA Director',
      role: 'State Emergency Management Director',
      phone: '+2348000000000', // Placeholder: Update with real number
      email: 'sema@benuestate.gov.ng',
      office: 'Benue SEMA Headquarters, Makurdi',
      lga: 'All',
      state: 'Benue',
      category: 'SEMA',
      priority: 1,
    ),
    AuthorityContact(
      name: 'Benue State Police Commissioner',
      role: 'Commissioner of Police',
      phone: '+2348000000001', // TODO: Update
      office: 'Benue State Police Command, Makurdi',
      lga: 'All',
      state: 'Benue',
      category: 'Police',
      priority: 1,
    ),

    // Nasarawa State
    AuthorityContact(
      name: 'Nasarawa SEMA Director',
      role: 'State Emergency Management Director',
      phone: '+2348000000002', // TODO: Update
      email: 'sema@nasarawastate.gov.ng',
      office: 'Nasarawa SEMA Headquarters, Lafia',
      lga: 'All',
      state: 'Nasarawa',
      category: 'SEMA',
      priority: 1,
    ),
    AuthorityContact(
      name: 'Nasarawa State Police Commissioner',
      role: 'Commissioner of Police',
      phone: '+2348000000003', // TODO: Update
      office: 'Nasarawa State Police Command, Lafia',
      lga: 'All',
      state: 'Nasarawa',
      category: 'Police',
      priority: 1,
    ),

    // Plateau State
    AuthorityContact(
      name: 'Plateau SEMA Director',
      role: 'State Emergency Management Director',
      phone: '+2348000000004', // TODO: Update
      email: 'sema@plateaustate.gov.ng',
      office: 'Plateau SEMA Headquarters, Jos',
      lga: 'All',
      state: 'Plateau',
      category: 'SEMA',
      priority: 1,
    ),
    AuthorityContact(
      name: 'Plateau State Police Commissioner',
      role: 'Commissioner of Police',
      phone: '+2348000000005', // TODO: Update
      office: 'Plateau State Police Command, Jos',
      lga: 'All',
      state: 'Plateau',
      category: 'Police',
      priority: 1,
    ),
  ];

  // ==================== LGA-LEVEL AUTHORITIES ====================

  /// Sample LGA authorities (Templates for all 53 LGAs)
  /// Note: These are placeholder contacts. Real numbers will be provided by state administrations.
  /// For now, these serve as templates for the UI and logic.
  static final List<AuthorityContact> _lgaAuthorities =
      _generateLGAAuthorities();

  static List<AuthorityContact> _generateLGAAuthorities() {
    final List<AuthorityContact> authorities = [];
    final allLGAs = MVPLocationsData.allLGAs;

    for (final lga in allLGAs) {
      // Chairman
      authorities.add(
        AuthorityContact(
          name: '${lga.name} LG Chairman',
          role: 'Local Government Chairman',
          phone: '+23480000${_generatePhoneSuffix(lga.name, 0)}',
          lga: lga.name,
          state: lga.state,
          category: 'LGA',
          priority: 1,
        ),
      );

      // DPO
      authorities.add(
        AuthorityContact(
          name: '${lga.name} DPO',
          role: 'Divisional Police Officer',
          phone: '+23480000${_generatePhoneSuffix(lga.name, 1)}',
          office: '${lga.name} Police Division',
          lga: lga.name,
          state: lga.state,
          category: 'Police',
          priority: 2,
        ),
      );

      // Extension Officer
      authorities.add(
        AuthorityContact(
          name: '${lga.name} Extension Officer',
          role: 'Agricultural Extension Officer',
          phone: '+23480000${_generatePhoneSuffix(lga.name, 2)}',
          lga: lga.name,
          state: lga.state,
          category: 'Extension',
          priority: 3,
        ),
      );
    }
    return authorities;
  }

  /// Helper to generate a consistent dummy suffix
  static String _generatePhoneSuffix(String name, int type) {
    // Generate a 4-digit suffix based on hash to be consistent but unique-ish
    final hash = (name.hashCode + type).abs() % 10000;
    return hash.toString().padLeft(4, '0');
  }

  // ==================== HELPER METHODS ====================

  /// Get all authorities for a specific LGA
  static List<AuthorityContact> getAuthoritiesForLGA(String lga, String state) {
    final authorities = <AuthorityContact>[];

    // Add state-level authorities
    authorities.addAll(_stateAuthorities.where((auth) => auth.state == state));

    // Add LGA-specific authorities
    authorities.addAll(
      _lgaAuthorities.where((auth) => auth.lga == lga && auth.state == state),
    );

    // Sort by priority (1 = highest)
    authorities.sort((a, b) => a.priority.compareTo(b.priority));

    return authorities;
  }

  /// Get phone numbers for alert distribution
  static List<String> getAlertPhoneNumbers({
    required String lga,
    required String state,
    required String severity,
  }) {
    final authorities = getAuthoritiesForLGA(lga, state);

    // For critical alerts: notify everyone
    if (severity.toLowerCase() == 'critical') {
      return authorities.map((auth) => auth.phone).toList();
    }

    // For high alerts: notify priority 1 & 2
    if (severity.toLowerCase() == 'high') {
      return authorities
          .where((auth) => auth.priority <= 2)
          .map((auth) => auth.phone)
          .toList();
    }

    // For medium/low: notify priority 1 only
    return authorities
        .where((auth) => auth.priority == 1)
        .map((auth) => auth.phone)
        .toList();
  }

  /// Get all state authorities
  static List<AuthorityContact> getStateAuthorities(String state) {
    return _stateAuthorities.where((auth) => auth.state == state).toList();
  }

  /// Get all LGA authorities
  static List<AuthorityContact> getAllLGAAuthorities() {
    return _lgaAuthorities;
  }

  /// Get authorities by category
  static List<AuthorityContact> getAuthoritiesByCategory(String category) {
    return [
      ..._stateAuthorities,
      ..._lgaAuthorities,
    ].where((auth) => auth.category == category).toList();
  }

  /// Get emergency hotline numbers (all priority 1)
  static List<String> getEmergencyHotlines(String state) {
    return _stateAuthorities
        .where((auth) => auth.state == state && auth.priority == 1)
        .map((auth) => auth.phone)
        .toList();
  }

  /// Check if authorities are configured for an LGA
  static bool isLGAConfigured(String lga, String state) {
    final authorities = getAuthoritiesForLGA(lga, state);
    // Check if  there are any non-placeholder numbers
    return authorities.any((auth) => !auth.phone.startsWith('+234800'));
  }

  /// Get configuration status
  static String getConfigurationStatus() {
    final configured = _lgaAuthorities
        .where((auth) => !auth.phone.startsWith('+234800'))
        .length;
    final total = _lgaAuthorities.length;

    return 'Authority contacts: $configured/$total configured (${(configured / total * 100).toStringAsFixed(1)}%)';
  }
}
