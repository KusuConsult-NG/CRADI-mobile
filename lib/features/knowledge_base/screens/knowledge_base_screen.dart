import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class KnowledgeBaseScreen extends StatelessWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Knowledge Base',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        actions: [
          GestureDetector(
            onTap: () => context.push('/profile'),
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primaryRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.account_circle,
                color: AppColors.primaryRed,
                size: 20,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search guides, hazards, or contacts...',
                  hintStyle: GoogleFonts.lexend(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Offline Status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.successGreen.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud_download,
                        color: AppColors.successGreen,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Offline Mode Available',
                            style: GoogleFonts.lexend(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Content downloaded successfully',
                            style: GoogleFonts.lexend(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: true,
                      activeThumbColor: AppColors.successGreen,
                      onChanged: (v) {},
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Favorites & Recent
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Favorites & Recent',
                    style: GoogleFonts.lexend(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: Text(
                      'See All',
                      style: GoogleFonts.lexend(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primaryRed,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildFavoriteCard(
                    'Flood Response Checklist',
                    'CHECKLIST',
                    AppColors.successGreen,
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuDvhi8e3ldWkMEkeaYGts6I6-X2jwkbSO3NvYLxwOmi-In3U4Dzoklw6e-vQr895640U3YXRO26NQm_oCRQdOAZvc9c_14EBvifESaiMHfxroaI9Z61S2mtZ4y1js0EskBXooo3URMoWHzZ3cKOQp6YaxaV4T1QDeg4iDEbG6a87H47b2ZdwsoQEd9cnO2WBRNfHVVY0RhZw2P8ZaR1aNI2kb51iYgX-OdiqJmMSYIhwNptLsSyYb3KaJ0OLcRj6f3kBIN5tq12kL7N',
                    context,
                  ),
                  const SizedBox(width: 12),
                  _buildFavoriteCard(
                    'Reporting a Wildfire',
                    'PROTOCOL',
                    Colors.orange,
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuDCOi0S_0IaRVAVZycsWjzrHO3tHP5iLg3yt3eNPYhLBG38iJO4ht_wwTQWLOLLBb8D4xVwWGEaL3DC0Ypm1IxadsAwVP-dRS-AUAOXoItsNjp_nySDDbxRyjW3SQT1ZJOHrc9SSGvFwzUhq0DXryIzT-mL5qSwLSOjEpPpxBR23Bb4ApbCFKSI8IMW3BLeJubx8SoXK0M5GU6uA_-03FxsjlFj54A74AvBirK1wLfQO0GnY1vV3E5znwKbpmqrypVCSqICjavIFuKk',
                    context,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Browse Categories
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Browse Categories',
                style: GoogleFonts.lexend(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _buildCategoryCard(
                  'Training Handbook',
                  'Certification modules',
                  Icons.menu_book,
                  Colors.blue,
                  () {
                    context.push(
                      '/knowledge-base/detail',
                      extra: {
                        'title': 'Training Handbook',
                        'category': 'Training',
                        'lastUpdated': '1 month ago',
                      },
                    );
                  },
                ),
                _buildCategoryCard(
                  'Hazard ID Guides',
                  'Identify local threats',
                  Icons.warning,
                  Colors.orange,
                  () {
                    context.push('/knowledge-base/guides');
                  },
                ),
                _buildCategoryCard(
                  'Response Protocols',
                  'Step-by-step actions',
                  Icons.health_and_safety,
                  Colors.green,
                  () {
                    context.push(
                      '/knowledge-base/detail',
                      extra: {
                        'title': 'Response Protocols',
                        'category': 'Protocols',
                        'lastUpdated': '2 weeks ago',
                      },
                    );
                  },
                ),
                _buildCategoryCard(
                  'Contacts Directory',
                  'Emergency services',
                  Icons.contacts,
                  Colors.purple,
                  () {
                    context.push('/contacts');
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Recently Updated
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Recently Updated',
                style: GoogleFonts.lexend(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      context.push(
                        '/knowledge-base/detail',
                        extra: {
                          'title': 'Flood Safety Guide 2024',
                          'category': 'Safety',
                          'lastUpdated': '2 days ago',
                        },
                      );
                    },
                    child: _buildRecentItem(
                      'Flood Safety Guide 2024',
                      'Updated safety protocols',
                      Icons.water,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      context.push(
                        '/knowledge-base/detail',
                        extra: {
                          'title': 'Community Response Plan',
                          'category': 'Emergency',
                          'lastUpdated': '1 week ago',
                        },
                      );
                    },
                    child: _buildRecentItem(
                      'Community Response Plan',
                      'New response strategies',
                      Icons.people,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      context.push(
                        '/knowledge-base/detail',
                        extra: {
                          'title': 'Weather Alert System',
                          'category': 'Tech',
                          'lastUpdated': '3 days ago',
                        },
                      );
                    },
                    child: _buildRecentItem(
                      'Weather Alert System',
                      'Alert notification guide',
                      Icons.notifications,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteCard(
    String title,
    String tag,
    Color tagColor,
    String imageUrl,
    BuildContext context,
  ) {
    return GestureDetector(
      onTap: () {
        context.push(
          '/knowledge-base/detail',
          extra: {
            'title': title,
            'category': tag,
            'lastUpdated': 'Recently saved',
          },
        );
      },
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          image: DecorationImage(
            image: NetworkImage(imageUrl),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bookmark,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: tagColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: GoogleFonts.lexend(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: GoogleFonts.lexend(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.lexend(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.lexend(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentItem(String title, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.grey.shade600, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.lexend(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.lexend(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.bookmark_border, color: Colors.grey),
        ],
      ),
    );
  }
}
