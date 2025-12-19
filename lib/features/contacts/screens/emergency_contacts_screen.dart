import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/contacts/models/emergency_contact_model.dart';
import 'package:climate_app/features/contacts/providers/emergency_contacts_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _categoryMap = {
    'All': 'all',
    'Coordinators': 'coordinator',
    'Emergency': 'emergency',
    'Agri-Extension': 'agri-extension',
  };
  String _selectedCategory = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _makePhoneCall(String phone) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch phone app')),
        );
      }
    }
  }

  Future<void> _sendSMS(String phone) async {
    final Uri launchUri = Uri(scheme: 'sms', path: phone);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch SMS app')),
        );
      }
    }
  }

  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final roleController = TextEditingController();
    final phoneController = TextEditingController();
    final orgController = TextEditingController();
    final lgaController = TextEditingController();
    String selectedCategory = 'coordinator';

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          'Add Emergency Contact',
          style: GoogleFonts.lexend(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: roleController,
                decoration: const InputDecoration(labelText: 'Role'),
              ),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              TextField(
                controller: orgController,
                decoration: const InputDecoration(
                  labelText: 'Organization (Optional)',
                ),
              ),
              TextField(
                controller: lgaController,
                decoration: const InputDecoration(labelText: 'LGA (Optional)'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const [
                  DropdownMenuItem(
                    value: 'coordinator',
                    child: Text('Coordinator'),
                  ),
                  DropdownMenuItem(
                    value: 'emergency',
                    child: Text('Emergency'),
                  ),
                  DropdownMenuItem(
                    value: 'agri-extension',
                    child: Text('Agri-Extension'),
                  ),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => selectedCategory = v ?? 'coordinator',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final provider = context.read<EmergencyContactsProvider>();
              final contact = EmergencyContact(
                id: '',
                name: nameController.text,
                role: roleController.text,
                phone: phoneController.text,
                organization: orgController.text.isEmpty
                    ? null
                    : orgController.text,
                lga: lgaController.text.isEmpty ? null : lgaController.text,
                category: selectedCategory,
              );

              try {
                await provider.addContact(contact);
                if (c.mounted) Navigator.pop(c);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contact added successfully')),
                  );
                }
              } on Exception catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<EmergencyContactsProvider>(
      context,
      listen: false,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: AppColors.textPrimary,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Emergency Contacts',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.primaryRed),
            onPressed: _showAddContactDialog,
          ),
        ],
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search name, LGA, or role',
                hintStyle: GoogleFonts.lexend(color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) => setState(() {}),
            ),
          ),

          // Category Filters
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _categoryMap.length,
              separatorBuilder: (c, i) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final entry = _categoryMap.entries.elementAt(index);
                final isSelected = _selectedCategory == entry.value;
                return ChoiceChip(
                  label: Text(entry.key),
                  selected: isSelected,
                  onSelected: (v) =>
                      setState(() => _selectedCategory = entry.value),
                  labelStyle: GoogleFonts.lexend(
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                  selectedColor: AppColors.primaryRed,
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected
                          ? Colors.transparent
                          : Colors.grey.shade200,
                    ),
                  ),
                  showCheckmark: false,
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Contacts List
          Expanded(
            child: StreamBuilder<List<EmergencyContact>>(
              stream: _selectedCategory == 'all'
                  ? provider.getContactsStream()
                  : provider.getContactsByCategory(_selectedCategory),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var contacts = snapshot.data ?? [];

                // Apply search filter
                if (_searchController.text.isNotEmpty) {
                  final query = _searchController.text.toLowerCase();
                  contacts = contacts
                      .where(
                        (c) =>
                            c.name.toLowerCase().contains(query) ||
                            c.role.toLowerCase().contains(query) ||
                            (c.lga?.toLowerCase().contains(query) ?? false),
                      )
                      .toList();
                }

                if (contacts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.contacts_outlined,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No contacts found',
                          style: GoogleFonts.lexend(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: contacts.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    return _buildContactCard(contact, provider);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _makePhoneCall('112'),
        backgroundColor: AppColors.errorRed,
        icon: const Icon(Icons.sos, color: Colors.white),
        label: Text(
          'Emergency 112',
          style: GoogleFonts.lexend(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard(
    EmergencyContact contact,
    EmergencyContactsProvider provider,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _getCategoryColor(contact.category).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getCategoryIcon(contact.category),
              color: _getCategoryColor(contact.category),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: GoogleFonts.lexend(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${contact.role}${contact.lga != null ? ' • ${contact.lga}' : ''}',
                  style: GoogleFonts.lexend(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _buildActionButton(
              Icons.sms,
              Colors.grey.shade100,
              Colors.grey.shade600,
              () => _sendSMS(contact.phone),
            ),
          ),
          _buildActionButton(
            Icons.call,
            AppColors.successGreen,
            Colors.white,
            () => _makePhoneCall(contact.phone),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    Color bg,
    Color fg,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: fg, size: 20),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'coordinator':
        return Colors.blue;
      case 'emergency':
        return AppColors.errorRed;
      case 'agri-extension':
        return AppColors.successGreen;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'coordinator':
        return Icons.person;
      case 'emergency':
        return Icons.local_police;
      case 'agri-extension':
        return Icons.agriculture;
      default:
        return Icons.contact_mail;
    }
  }
}
