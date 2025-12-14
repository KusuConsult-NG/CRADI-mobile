import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/core/providers/language_provider.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:climate_app/features/profile/providers/profile_provider.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedFilterIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            // Simulate refresh or reload data
            await Future.delayed(const Duration(seconds: 1));
            if (context.mounted) {
              // Reload profile or reports if needed
            }
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(), // Include Header in scrollable area
                // Main Content Body (formerly Expanded)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Greeting
                      Consumer<LanguageProvider>(
                        builder: (context, language, child) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              language.greeting,
                              style: GoogleFonts.lexend(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.lexend(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                                children: [
                                  const TextSpan(text: 'You have '),
                                  TextSpan(
                                    text: language
                                        .attentionText, // Simplified for demo
                                    style: GoogleFonts.lexend(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Quick Stats
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => context.push('/reports-status'),
                                child: _buildStatCard(
                                  count: '12',
                                  label: 'Active',
                                  icon: Icons.warning_amber,
                                  color: AppColors.warningYellow,
                                  bgColor: AppColors.warningYellow.withValues(
                                    alpha: 0.1,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => context.push('/reports-status'),
                                child: _buildStatCard(
                                  count: '4',
                                  label: 'Pending',
                                  icon: Icons.schedule,
                                  color: Colors.orange,
                                  bgColor: Colors.orange.withValues(alpha: 0.1),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => context.push('/reports-status'),
                                child: _buildStatCard(
                                  count: '28',
                                  label: 'Resolved',
                                  icon: Icons.check_circle,
                                  color: AppColors.successGreen,
                                  bgColor: AppColors.successGreen.withValues(
                                    alpha: 0.1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Browse Categories
                      _buildSectionHeader('Browse Categories', () {}),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildCategoryCard(
                              'Floods',
                              Icons.flood,
                              Colors.blue,
                            ),
                            _buildCategoryCard(
                              'Droughts',
                              Icons.wb_sunny,
                              Colors.orange,
                            ),
                            _buildCategoryCard(
                              'Pests',
                              Icons.pest_control,
                              Colors.green,
                            ),
                            _buildCategoryCard(
                              'Conflicts',
                              Icons.shield,
                              Colors.red,
                            ),
                            _buildCategoryCard(
                              'Erosion',
                              Icons.landscape,
                              Colors.brown,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Biometrics Card Removed

                      // Filter Tabs (Sticky-ish behavior handled by placement here)
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFE7F3EB,
                          ), // Light greenish tint from design, adapted
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          children: [
                            _buildFilterTab(0, 'To Verify'),
                            _buildFilterTab(1, 'Alerts'),
                            _buildFilterTab(2, 'My Reports'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Feed Content
                      _buildFeedContent(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => context.push('/profile'),
                child: Consumer<ProfileProvider>(
                  builder: (context, profile, _) {
                    if (profile.profileImagePath != null) {
                      return Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primaryRed,
                            width: 2,
                          ),
                          image: DecorationImage(
                            image: FileImage(File(profile.profileImagePath!)),
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    }
                    return Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.shade300,
                        border: Border.all(
                          color: AppColors.primaryRed,
                          width: 2,
                        ),
                      ),
                      child: const Icon(Icons.person, color: Colors.grey),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MONITORING ZONE',
                    style: GoogleFonts.lexend(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Consumer<ProfileProvider>(
                    builder: (context, profile, _) => Row(
                      children: [
                        Text(
                          profile.monitoringZone ?? 'Benue State',
                          style: GoogleFonts.lexend(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.expand_more,
                          size: 18,
                          color: AppColors.textPrimary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              GestureDetector(
                onTap: () => context.push('/chat'),
                child: Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    color: AppColors.textPrimary,
                    size: 20,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  // Notification action
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No new notifications')),
                  );
                },
                child: Stack(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.notifications_outlined,
                        color: AppColors.textPrimary,
                        size: 22,
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 12,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.errorRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String count,
    required String label,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                Icon(
                  Icons.arrow_forward,
                  color: Colors.grey.shade300,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count,
                  style: GoogleFonts.lexend(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.lexend(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab(int index, String label) {
    final bool isSelected = _selectedFilterIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilterIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.lexend(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeedContent() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Center(child: Text('Please log in to view reports'));
    }

    // Build query based on selected tab
    Query<Map<String, dynamic>> query;

    if (_selectedFilterIndex == 0) {
      // To Verify - pending reports
      query = FirebaseFirestore.instance
          .collection('reports')
          .where('status', isEqualTo: 'pending')
          .orderBy('submittedAt', descending: true)
          .limit(10);
    } else if (_selectedFilterIndex == 1) {
      // Alerts - high/critical severity or alerts
      query = FirebaseFirestore.instance
          .collection('reports')
          .where('isAlert', isEqualTo: true)
          .orderBy('submittedAt', descending: true)
          .limit(10);
    } else {
      // My Reports - user's own reports
      query = FirebaseFirestore.instance
          .collection('reports')
          .where('userId', isEqualTo: currentUser.uid)
          .orderBy('submittedAt', descending: true)
          .limit(10);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final reports = snapshot.data?.docs ?? [];

        if (reports.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _selectedFilterIndex == 0
                        ? 'No reports to verify'
                        : _selectedFilterIndex == 1
                        ? 'No active alerts'
                        : 'No reports yet',
                    style: GoogleFonts.lexend(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedFilterIndex == 2
                        ? 'Reports you submit will appear here'
                        : 'New items will appear here',
                    style: GoogleFonts.lexend(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            if (_selectedFilterIndex == 1 && reports.isNotEmpty) ...[
              // Show first alert as featured
              _buildAlertCardFromData(reports.first.data()),
              const SizedBox(height: 16),
            ],
            ...reports.map((doc) {
              final data = doc.data();
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildReportCard(data, doc.id),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback onViewAll) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.lexend(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        GestureDetector(
          onTap: onViewAll,
          child: Text(
            'See All',
            style: GoogleFonts.lexend(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryRed,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(String label, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.lexend(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> data, String docId) {
    final hazardType = data['hazardType'] ?? 'Unknown';
    final severity = data['severity'] ?? 'Unknown';
    final location = data['locationDetails'] ?? 'Unknown location';
    final timestamp = data['submittedAt'] as Timestamp?;
    final timeAgo = timestamp != null
        ? _formatTimeAgo(timestamp.toDate())
        : 'Unknown time';

    // Map hazard  types to icons
    IconData icon;
    Color iconColor;
    switch (hazardType.toLowerCase()) {
      case 'flood':
        icon = Icons.flood;
        iconColor = Colors.blue;
        break;
      case 'drought':
        icon = Icons.wb_sunny;
        iconColor = Colors.orange;
        break;
      case 'pest':
        icon = Icons.pest_control;
        iconColor = Colors.green;
        break;
      case 'fire':
        icon = Icons.local_fire_department;
        iconColor = Colors.red;
        break;
      default:
        icon = Icons.warning;
        iconColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: iconColor.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$hazardType - $severity',
                        style: GoogleFonts.lexend(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location,
                        style: GoogleFonts.lexend(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.schedule,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      timeAgo,
                      style: GoogleFonts.lexend(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCardFromData(Map<String, dynamic> data) {
    final hazardType = data['hazardType'] ?? 'Alert';
    final severity = data['severity'] ?? 'High';
    final description = data['description'] ?? 'No description available';
    final location = data['locationDetails'] ?? 'Unknown location';
    final timestamp = data['submittedAt'] as Timestamp?;
    final timeAgo = timestamp != null
        ? _formatTimeAgo(timestamp.toDate())
        : 'Unknown time';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.errorRed,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.warning,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ALERT',
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer, size: 14, color: Color(0xFFA50E0E)),
                    const SizedBox(width: 4),
                    Text(
                      timeAgo,
                      style: GoogleFonts.lexend(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFA50E0E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$hazardType - $severity Severity',
            style: GoogleFonts.lexend(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$location - $description',
            style: GoogleFonts.lexend(
              fontSize: 14,
              color: AppColors.textPrimary.withValues(alpha: 0.8),
              height: 1.5,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }
}
