import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/shared/widgets/custom_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.primaryRed,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Help & Support',
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.shade200, height: 1.0),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Frequently Asked Questions',
              style: GoogleFonts.lexend(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _buildExpansionTile(
              'How do I report a hazard?',
              'Navigate to the "Report" tab or tap the "+" button on the dashboard. Select the hazard type, add photos/videos, and submit your report.',
            ),
            _buildExpansionTile(
              'What do the alert colors mean?',
              'Red indicates high severity (immediate danger), Orange is medium, and Yellow is low. Blue typically indicates water-related hazards like floods.',
            ),
            _buildExpansionTile(
              'Can I report without internet?',
              'Yes! Use "Offline Mode" in Settings. Your reports will be saved locally and can be synced when you go online.',
            ),
            _buildExpansionTile(
              'How do I verify other reports?',
              'Go to "Alerts" and look for pending reports nearby. You can confirm or reject them based on your observation.',
            ),
            const SizedBox(height: 32),
            Text(
              'Still need help?',
              style: GoogleFonts.lexend(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            CustomButton(
              text: 'Contact Support',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Support contact feature coming soon'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpansionTile(String title, String content) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        title: Text(
          title,
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              content,
              style: GoogleFonts.lexend(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
