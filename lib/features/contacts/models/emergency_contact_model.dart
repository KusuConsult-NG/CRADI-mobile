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

  factory EmergencyContact.fromFirestore(Map<String, dynamic> data, String id) {
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

  factory EmergencyContact.fromAppwrite(Map<String, dynamic> data, String id) {
    return EmergencyContact(
      id: id,
      name: data['name'] as String? ?? '',
      role: data['relationship'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      organization: null,
      lga: null,
      category: 'other',
      isAvailable: true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'role': role,
      'phone': phone,
      if (organization != null) 'organization': organization,
      if (lga != null) 'lga': lga,
      'category': category,
      'isAvailable': isAvailable,
    };
  }

  Map<String, dynamic> toAppwrite() {
    return {'name': name, 'phone': phone, 'relationship': role};
  }
}
