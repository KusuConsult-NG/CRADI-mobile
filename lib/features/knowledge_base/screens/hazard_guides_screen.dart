import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/knowledge_base/providers/knowledge_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class HazardGuidesScreen extends StatefulWidget {
  const HazardGuidesScreen({super.key});

  @override
  State<HazardGuidesScreen> createState() => _HazardGuidesScreenState();
}

class _HazardGuidesScreenState extends State<HazardGuidesScreen> {
  int _selectedFilterIndex = 0;
  final List<String> _filters = [
    'All',
    'Hydrological',
    'Meteorological',
    'Agricultural',
    'Safety',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<KnowledgeProvider>().fetchGuides(
        category: _filters[_selectedFilterIndex],
      );
    });
  }

  void _onFilterSelected(int index) {
    setState(() => _selectedFilterIndex = index);
    final category = _filters[index];
    context.read<KnowledgeProvider>().fetchGuides(category: category);
  }

  @override
  Widget build(BuildContext context) {
    final knowledgeProvider = context.watch<KnowledgeProvider>();

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
            icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
            onPressed: () => knowledgeProvider.fetchGuides(
              category: _filters[_selectedFilterIndex],
            ),
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
          RefreshIndicator(
            onRefresh: () => knowledgeProvider.fetchGuides(
              category: _filters[_selectedFilterIndex],
            ),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                        onChanged: knowledgeProvider.searchGuides,
                        decoration: InputDecoration(
                          hintText: 'Search guides, signs, or hazards...',
                          hintStyle: GoogleFonts.lexend(
                            color: Colors.grey.shade500,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: Colors.grey.shade500,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
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
                          onSelected: (v) => _onFilterSelected(index),
                          labelStyle: GoogleFonts.lexend(
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : Colors.grey.shade700,
                            fontSize: 14,
                          ),
                          selectedColor: AppColors.primaryRed,
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
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

                  const SizedBox(height: 24),

                  if (knowledgeProvider.isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (knowledgeProvider.error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 40,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              knowledgeProvider.error!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.lexend(color: Colors.red),
                            ),
                            TextButton(
                              onPressed: () => knowledgeProvider.fetchGuides(
                                category: _filters[_selectedFilterIndex],
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (knowledgeProvider.guides.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40.0),
                        child: Column(
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 60,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No guides found for this category',
                              style: GoogleFonts.lexend(
                                color: Colors.grey.shade500,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    // All Guides Grid
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: knowledgeProvider.guides.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.75,
                          ),
                      itemBuilder: (context, index) {
                        final guide = knowledgeProvider.guides[index];
                        return _buildGuideCard(
                          guide['title'] ?? 'No Title',
                          guide['subtitle'] ?? guide['category'] ?? 'Manual',
                          guide['tag'] ?? 'GUIDE',
                          _getTagColor(guide['tag']),
                          guide['imageUrl'] ??
                              'https://via.placeholder.com/300x400',
                          isDownloaded: guide['isOffline'] ?? true,
                          onTap: () {
                            context.push(
                              '/knowledge-base/detail',
                              extra: guide,
                            );
                          },
                        );
                      },
                    ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getTagColor(String? tag) {
    if (tag == null) return Colors.blue;
    switch (tag.toUpperCase()) {
      case 'HIGH PRIORITY':
      case 'IMMEDIATE':
        return Colors.red;
      case 'MODERATE':
      case 'WATCH':
        return Colors.orange;
      case 'SLOW ONSET':
        return Colors.yellow;
      default:
        return Colors.blue;
    }
  }

  Widget _buildGuideCard(
    String title,
    String subtitle,
    String tag,
    Color tagColor,
    String imageUrl, {
    bool isDownloaded = true,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          image: DecorationImage(
            image: NetworkImage(imageUrl),
            fit: BoxFit.cover,
            onError: (e, s) =>
                const AssetImage('assets/images/placeholder.png'),
          ),
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
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.3),
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
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDownloaded ? Icons.download_done : Icons.cloud_download,
                  color: isDownloaded ? AppColors.successGreen : Colors.white,
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
                      color: tagColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: tagColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      tag,
                      style: GoogleFonts.lexend(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: tagColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: GoogleFonts.lexend(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.lexend(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                    maxLines: 1,
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
}
