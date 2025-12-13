import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedFilterIndex = 0;
  final List<String> _filters = ['All', 'Coordinators', 'Emergency', 'Agri-Extension'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.textPrimary),
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
            icon: const Icon(Icons.cloud_done, color: AppColors.textPrimary),
            onPressed: () {},
          ),
        ],
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100), // Space for FAB
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),

                // Filters
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: _filters.length,
                    separatorBuilder: (c, i) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final isSelected = _selectedFilterIndex == index;
                      return ChoiceChip(
                        label: Text(_filters[index]),
                        selected: isSelected,
                        onSelected: (v) => setState(() => _selectedFilterIndex = index),
                        labelStyle: GoogleFonts.lexend(
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                        ),
                        selectedColor: AppColors.primaryRed,
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade200),
                        ),
                        showCheckmark: false,
                        avatar: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),
                
                // Meta Info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.successGreen, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(
                        'Available offline • Updated Today 08:30 AM',
                        style: GoogleFonts.lexend(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // LDP Coordinators
                _buildSectionHeader('LDP Coordinators'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _buildContactChange(
                        name: 'Musa Ibrahim',
                        detail: 'Coordinator • Makurdi LGA',
                        icon: Icons.person,
                        iconColor: Colors.blue,
                        iconBg: Colors.blue.shade50,
                      ),
                      const SizedBox(height: 12),
                      _buildContactChange(
                        name: 'Sarah Okafor',
                        detail: 'Coordinator • Guma LGA',
                        icon: Icons.person,
                        iconColor: Colors.blue,
                        iconBg: Colors.blue.shade50,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Emergency Services
                _buildSectionHeader('Emergency Services'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _buildContactChange(
                        name: 'State Police Command',
                        detail: 'Hotline • All LGAs',
                        icon: Icons.local_police,
                        iconColor: AppColors.errorRed,
                        iconBg: AppColors.errorRed.withValues(alpha: 0.1),
                      ),
                      const SizedBox(height: 12),
                      _buildContactChange(
                        name: 'SEMA Rapid Response',
                        detail: 'Disaster Relief • Makurdi HQ',
                        icon: Icons.medical_services,
                        iconColor: Colors.orange,
                        iconBg: Colors.orange.shade50,
                        showSms: false,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Agri-Extension
                _buildSectionHeader('Agri-Extension Officers'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildContactChange(
                    name: 'Emmanuel Dauda',
                    detail: 'Livestock Specialist • Gwer West',
                    icon: Icons.agriculture,
                    iconColor: AppColors.successGreen,
                    iconBg: AppColors.successGreen.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
          ),

          // Sticky Bottom Action
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.errorRed,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 8,
                shadowColor: AppColors.errorRed.withValues(alpha: 0.4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sos),
                  const SizedBox(width: 8),
                  Text(
                    'Call National Emergency (112)',
                    style: GoogleFonts.lexend(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.lexend(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
      ),
    );
  }

  Widget _buildContactChange({
    required String name,
    required String detail,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    bool showSms = true,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.lexend(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text(
                  detail,
                  style: GoogleFonts.lexend(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          if (showSms)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildActionButton(Icons.sms, Colors.grey.shade100, Colors.grey.shade600, () {}),
            ),
          _buildActionButton(Icons.call, AppColors.successGreen, Colors.white, () {}),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, Color bg, Color fg, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: fg, size: 20),
      ),
    );
  }
}
