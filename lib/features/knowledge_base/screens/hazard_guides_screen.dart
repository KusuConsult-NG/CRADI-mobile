import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class HazardGuidesScreen extends StatefulWidget {
  const HazardGuidesScreen({super.key});

  @override
  State<HazardGuidesScreen> createState() => _HazardGuidesScreenState();
}

class _HazardGuidesScreenState extends State<HazardGuidesScreen> {
  int _selectedFilterIndex = 0;
  final List<String> _filters = ['All', 'Hydrological', 'Meteorological', 'Agricultural'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Column(
          children: [
            Text(
              'Hazard Guides',
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                fontSize: 18,
              ),
            ),
            Text(
              'KNOWLEDGE BASE',
              style: GoogleFonts.lexend(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
                fontSize: 10,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.cloud_download, color: AppColors.textPrimary),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.successGreen,
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 1.5)),
                    ),
                  ),
                ),
              ],
            ),
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
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search guides, signs, or hazards...',
                        hintStyle: GoogleFonts.lexend(color: Colors.grey.shade500),
                        prefixIcon: Icon(Icons.search, color: Colors.grey.shade500),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
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
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.black : Colors.grey.shade700,
                          fontSize: 14,
                        ),
                        selectedColor: AppColors.successGreen,
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade200),
                        ),
                        showCheckmark: isSelected,
                        checkmarkColor: Colors.black,
                      );
                    },
                  ),
                ),

                const SizedBox(height: 24),

                // Seasonal Watchlist
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Seasonal Watchlist', style: GoogleFonts.lexend(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      Text('View All', style: GoogleFonts.lexend(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.successGreen)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      image: const DecorationImage(
                        image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuDSMI6Li_EB3bi8nzMOtxAK9-MKgCOzv0QVgVIXin-gtHHCZtU9i4j6HfyGu2U6LF3UWGXr7zOmHPuGNMBG_sXa9-6JkC0yOGTvAh9HbNhasZ5mfp8xJ8jIfkNdd8yV4iK5FYLVHuzbbQp7RxUpZ_8owYqkuffHLkj9EHVChJeLXXN_DliHG2213JIA92BN8GVVvC9Q21SpmQ55lcVo513IWq50tinIPgUOeDtJnB800u7Id1zNDVQGdUk4H3ecjM2sZzSKbbWDB6f_'),
                        fit: BoxFit.cover,
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6), Colors.black.withValues(alpha: 0.9)],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.errorRed.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning, color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text('HIGH PRIORITY', style: GoogleFonts.lexend(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('HYDROLOGICAL', style: GoogleFonts.lexend(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.successGreen)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.download_done, color: AppColors.successGreen, size: 14),
                                        const SizedBox(width: 4),
                                        Text('Offline Ready', style: GoogleFonts.lexend(fontSize: 10, color: Colors.white.withValues(alpha: 0.8))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('Riverine Flooding', style: GoogleFonts.lexend(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                              const SizedBox(height: 4),
                              Text('Key indicators: Rising water marks, soil saturation, debris flow.', style: GoogleFonts.lexend(fontSize: 12, color: Colors.grey.shade300)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // All Guides Grid
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('All Guides', style: GoogleFonts.lexend(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.75,
                  children: [
                    _buildGuideCard(
                      'Drought Signs',
                      'Crop yellowing & soil cracks',
                      'SLOW ONSET',
                      Colors.yellow,
                      'https://lh3.googleusercontent.com/aida-public/AB6AXuBYOxziCZZZV_Nhsobgf5mMkiCd7hhw-5ICSbK9Iq-OhNQsfrN_iDuVGMjxuSELOrfYrCKWgA1pFoza4zsMTqkc-WhPTXt5W9p8DVnsuGiEUGZTEER6J9pJEYlTyarTjSaRpG16eGUQVR91-lwRWm04N2HfaG2msShz7kupBzHoZqt94D6TboeBqLMBrBQiSww_CsMuAfnlF1vdDj3YwLesS39XkLfu6QcAY-wgRg36mA0IZvwKKXzvM-qtc50qCVIDHWwyqCkn9EKN',
                    ),
                    _buildGuideCard(
                      'Pest Infestation',
                      'Fall Armyworm ID',
                      'MODERATE',
                      Colors.orange,
                      'https://lh3.googleusercontent.com/aida-public/AB6AXuDoZB9DEwMwzwayKAu2o65UKt2U00fMPw3NGBtya-HDc7j3kHERJqHY2IK1df5ojflflMu0-Hd7MQJLP-jAJ8ccpziPNlI7qMzHqFgLWqSqNBMoa8M24HtUcULVelj2jxXrplzKd9ei81nU-Nwqis-WK2K8Rrbafk48DuAPJLDBVZ9LVfYI_UdkqXf4pqA4z6v7e5NNwde5N9B8vNCtWZawH9zxo1_tT3y8Ul_-iEs-v_VfHxRQT83RrSrj5TTOj9GB9XZbI9XZdKdP',
                      isDownloaded: false,
                    ),
                    _buildGuideCard(
                      'Severe Wind',
                      'Structural damage risks',
                      'IMMEDIATE',
                      Colors.red,
                      'https://lh3.googleusercontent.com/aida-public/AB6AXuBz6yb4vpX_KDxbjlLM9iQ8HFfrgsFB1___CpnuVn0S0q5no2ZgzwteKYiZarXBbmAzhAMK8tjss4XPV3IbFIPJf9d2WEQgSIAk4SQtbTWmjLaPedqOqayxSDA93D02IKOpb_lkBBFHEtOCfkRfaawhUU4CXJhRmhHcNvAewcIXZxnXeeKzKB0i8E3xEMQjvMVqFnjXGdQ70TDqudqdvihvEOzAMFx_tFQD0JZtCsWlcMnXNAAWlH6RHAgHK0QDIMKbfwSzS0hknr6L',
                    ),
                    _buildGuideCard(
                      'Extreme Heat',
                      'Heat stress indicators',
                      'WATCH',
                      Colors.yellow,
                      'https://lh3.googleusercontent.com/aida-public/AB6AXuCXEaagMJgQZxCJk0rLmO6TIR9bBoKXYuGuWm1wf5hma-4X002gpGQ_n70xFRgQPOhlPXbczv3NRf3tdYmd0g6QilvTRyaCcQHlj-DrHVSbC7wy1l2jelmbrKSDZ8v65lDmjN6oM0P8X-7GDjf_d7Dx9hPLPoOczcLJFogLnz_9P-o0a6G8NfwdnYcdJodyadUELdyAJazQeCi6bTHSCs6-GhkTWFBx7qKVYRfXb0leEW7ohRUAWL2aEkGLSiewvGjgHUG-zq-rBc5n',
                      isDownloaded: false,
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                Center(
                  child: TextButton.icon(
                    onPressed: () {},
                    icon: const Text('View Archived Guides'),
                    label: const Icon(Icons.arrow_forward),
                    style: TextButton.styleFrom(foregroundColor: AppColors.successGreen),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 32,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                 FloatingActionButton(
                  onPressed: () {},
                  backgroundColor: AppColors.successGreen,
                  child: const Icon(Icons.camera_alt, color: Colors.black, size: 28),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)),
                  child: Text('Quick Identify', style: GoogleFonts.lexend(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideCard(String title, String subtitle, String tag, Color tagColor, String imageUrl, {bool isDownloaded = true}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        image: DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover),
        color: Colors.grey.shade900,
      ),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.3), Colors.black.withValues(alpha: 0.8)],
              ),
            ),
          ),
           Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
              child: Icon(isDownloaded ? Icons.download_done : Icons.cloud_download, color: isDownloaded ? AppColors.successGreen : Colors.white, size: 16),
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: tagColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: tagColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(tag, style: GoogleFonts.lexend(fontSize: 10, fontWeight: FontWeight.bold, color: tagColor)),
                ),
                const SizedBox(height: 6),
                Text(title, style: GoogleFonts.lexend(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.lexend(fontSize: 12, color: Colors.grey.shade400)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
