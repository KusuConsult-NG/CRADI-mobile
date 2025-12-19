import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class KnowledgeDetailScreen extends StatelessWidget {
  final Map<String, dynamic> guide;

  const KnowledgeDetailScreen({super.key, required this.guide});

  @override
  Widget build(BuildContext context) {
    // Determine category icon and color
    IconData categoryIcon = Icons.info_outline;
    Color categoryColor = AppColors.primaryRed;

    switch (guide['category']) {
      case 'Safety':
        categoryIcon = Icons.security;
        categoryColor = Colors.blue;
        break;
      case 'Emergency':
        categoryIcon = Icons.warning_amber_rounded;
        categoryColor = Colors.orange;
        break;
      case 'Tech':
        categoryIcon = Icons.smartphone;
        categoryColor = Colors.purple;
        break;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Guide Detail',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.share_outlined,
              color: AppColors.textPrimary,
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(
              Icons.bookmark_border,
              color: AppColors.textPrimary,
            ),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: categoryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: categoryColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(categoryIcon, size: 14, color: categoryColor),
                  const SizedBox(width: 6),
                  Text(
                    guide['category'] ?? 'General',
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: categoryColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              guide['title'],
              style: GoogleFonts.lexend(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Updated ${guide['lastUpdated'] ?? 'recently'}',
                  style: GoogleFonts.lexend(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.menu_book, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  '5 min read',
                  style: GoogleFonts.lexend(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Featured Image Placeholder
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
                image: const DecorationImage(
                  image: NetworkImage(
                    'https://images.unsplash.com/photo-1544465554-044abc734aa0?auto=format&fit=crop&w=800&q=80',
                  ),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildContentSection(
              'Overview',
              'This guide provides comprehensive safety protocols and essential information regarding ${guide['title'].toLowerCase()} in Nigeria. It is designed to help monitors and community members respond effectively to changing environmental conditions.',
            ),
            const SizedBox(height: 20),
            _buildContentSection(
              'Key Steps',
              '1. Assess the situation and identify immediate risks.\n2. Coordinate with local authorities and emergency services.\n3. Communicate clear instructions to the community.\n4. Document and report findings through the CRADI app.',
            ),
            const SizedBox(height: 20),
            _buildContentSection(
              'Safety Checklist',
              '• Ensure personal safety equipment is ready.\n• Maintain communication with the control center.\n• Monitor local weather alerts and news updates.\n• Have emergency contact numbers easily accessible.',
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),
            Text(
              'Related Topics',
              style: GoogleFonts.lexend(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _buildRelatedItem(
              'Emergency Evacuation Routes',
              Icons.directions_run,
            ),
            _buildRelatedItem(
              'First Aid Basics for Incidents',
              Icons.medical_services_outlined,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.lexend(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          content,
          style: GoogleFonts.lexend(
            fontSize: 16,
            height: 1.6,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildRelatedItem(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.primaryRed),
        ),
        title: Text(
          title,
          style: GoogleFonts.lexend(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 12,
          color: Colors.grey,
        ),
        onTap: () {},
      ),
    );
  }
}
