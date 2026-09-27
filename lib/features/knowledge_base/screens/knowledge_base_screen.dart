import 'dart:developer' as developer;
import 'package:climate_app/core/providers/connectivity_provider.dart';
import 'package:climate_app/features/knowledge_base/providers/news_provider.dart';
import 'package:climate_app/features/knowledge_base/providers/knowledge_provider.dart';
import 'package:climate_app/core/theme/app_colors.dart';
import 'package:climate_app/features/knowledge_base/guide_bookmarks.dart';
import 'package:climate_app/features/knowledge_base/widgets/guide_bookmark_button.dart';
import 'package:climate_app/features/knowledge_base/knowledge_categories.dart';
import 'package:climate_app/features/knowledge_base/widgets/guide_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:climate_app/core/l10n/l10n.dart';

class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Saved guides are read from storage once; the bookmark buttons and the
    // "Saved" filter on the guides list share this one state.
    GuideBookmarks().load();
    Future.microtask(() {
      if (mounted) {
        context.read<NewsProvider>().fetchNews();
        context.read<KnowledgeProvider>().fetchGuides(category: 'All');
      }
    });
  }

  List<Map<String, dynamic>> _getFilteredNews(
    List<Map<String, dynamic>> newsItems,
  ) {
    if (_searchQuery.isEmpty) return newsItems;
    return newsItems
        .where(
          (item) => (item['title']?.toString() ?? '').toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ),
        )
        .toList();
  }

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
        title: Text(
          context.l10n.knowledgeBaseTitle,
          style: GoogleFonts.lexend(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background.withValues(alpha: 0.95),
        elevation: 0,
        actions: [
          Semantics(
            button: true,
            label: context.l10n.myProfile,
            child: Tooltip(
              message: context.l10n.myProfile,
              child: GestureDetector(
                onTap: () => context.push('/profile'),
                // 48pt hit area around the 32pt avatar.
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primaryRed.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const ExcludeSemantics(
                      child: Icon(
                        Icons.account_circle,
                        color: AppColors.primaryRed,
                        size: 20,
                      ),
                    ),
                  ),
                ),
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
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: context.l10n.knowledgeBaseSearchHint,
                  hintStyle: GoogleFonts.lexend(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          tooltip: context.l10n.commonClearSearch,
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
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
              child: Consumer<ConnectivityProvider>(
                builder: (context, connectivity, _) {
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
                            color: AppColors.successGreen.withValues(
                              alpha: 0.1,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            connectivity.isOffline
                                ? Icons.cloud_off
                                : Icons.cloud_download,
                            color: connectivity.isOffline
                                ? Colors.grey
                                : AppColors.successGreen,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                connectivity.manualOffline
                                    ? context.l10n.knowledgeOfflineActive
                                    : context.l10n.knowledgeOfflineAvailable,
                                style: GoogleFonts.lexend(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                connectivity.manualOffline
                                    ? context.l10n.knowledgeUsingCache
                                    : context.l10n.knowledgeContentDownloaded,
                                style: GoogleFonts.lexend(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: connectivity.manualOffline,
                          activeThumbColor: AppColors.successGreen,
                          onChanged: (v) => connectivity.setManualOffline(v),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Recent Guides (From Provider)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.l10n.knowledgeFeaturedGuides,
                    style: GoogleFonts.lexend(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      context.push('/knowledge-base/guides');
                    },
                    child: Text(
                      context.l10n.seeAll,
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
              child: Consumer<KnowledgeProvider>(
                builder: (context, knowledgeProvider, _) {
                  if (knowledgeProvider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allGuides = knowledgeProvider.searchGuides(
                    _searchQuery,
                  );

                  final error = knowledgeProvider.error;
                  if (allGuides.isEmpty && error != null) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            error(context.l10n),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.lexend(color: Colors.red),
                          ),
                          TextButton(
                            onPressed: () => knowledgeProvider.fetchGuides(
                              category: allKnowledgeCategories,
                            ),
                            child: Text(context.l10n.retry),
                          ),
                        ],
                      ),
                    );
                  }

                  if (allGuides.isEmpty) {
                    return Center(
                      child: Text(
                        _searchQuery.trim().isEmpty
                            ? context.l10n.knowledgeNoGuides
                            : context.l10n.knowledgeNoGuidesMatch(
                                _searchQuery.trim(),
                              ),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.lexend(color: Colors.grey),
                      ),
                    );
                  }

                  // Take top 5 for featured
                  final featuredGuides = allGuides.take(5).toList();

                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: featuredGuides.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final guide = featuredGuides[index];
                      // Determine tag color
                      Color tagColor = Colors.blue;
                      final tag =
                          guide['tag']?.toString().toUpperCase() ?? 'GUIDE';
                      if (tag == 'IMMEDIATE' || tag == 'HIGH PRIORITY') {
                        tagColor = Colors.red;
                      } else if (tag == 'WATCH' || tag == 'MODERATE') {
                        tagColor = Colors.orange;
                      }

                      return _buildFavoriteCard(
                        guide['title'] ?? context.l10n.knowledgeNoTitle,
                        knowledgeTagDisplay(context.l10n, guide['tag']),
                        tagColor,
                        context,
                        guideData: guide,
                      );
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // Browse Categories
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                context.l10n.browseCategories,
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
                  context.l10n.knowledgeHazardIdGuides,
                  context.l10n.knowledgeHazardIdGuidesDesc,
                  Icons.warning,
                  Colors.orange,
                  () {
                    context.push('/knowledge-base/guides');
                  },
                ),
                _buildCategoryCard(
                  context.l10n.knowledgeFireResponse,
                  context.l10n.knowledgeFireResponseDesc,
                  Icons.local_fire_department,
                  Colors.red,
                  () {
                    context.push('/knowledge-base/guides', extra: 'Fire');
                  },
                ),
                _buildCategoryCard(
                  context.l10n.knowledgeFloodReadiness,
                  context.l10n.knowledgeFloodReadinessDesc,
                  Icons.water_drop,
                  Colors.blue,
                  () {
                    context.push('/knowledge-base/guides', extra: 'Flood');
                  },
                ),
                _buildCategoryCard(
                  context.l10n.knowledgeContactsDirectory,
                  context.l10n.knowledgeContactsDirectoryDesc,
                  Icons.contacts,
                  Colors.purple,
                  () {
                    context.push('/contacts');
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Recently Updated (External News)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                context.l10n.knowledgeExternalNews,
                style: GoogleFonts.lexend(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Consumer<NewsProvider>(
              builder: (context, newsProvider, _) {
                if (newsProvider.isLoading) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (newsProvider.error != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        newsProvider.error!(context.l10n),
                        style: GoogleFonts.lexend(color: Colors.red),
                      ),
                    ),
                  );
                }

                final news = _getFilteredNews(newsProvider.newsItems);

                if (news.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        context.l10n.knowledgeNoNews,
                        style: GoogleFonts.lexend(color: Colors.grey),
                      ),
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: news.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          onTap: () async {
                            final url = item['url'];
                            if (url is String && url.startsWith('http')) {
                              try {
                                final uri = Uri.parse(url);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                } else {
                                  developer.log('Could not launch news: $url');
                                }
                              } on Exception catch (e) {
                                developer.log('Error launching news: $e');
                              }
                            }
                          },
                          child: _buildRecentItem(
                            item['title'] ?? context.l10n.knowledgeNoTitle,
                            [
                                  item['source'],
                                  formatKnowledgeDate(
                                    item['date'],
                                    context.intlLocale,
                                  ),
                                ]
                                .where((p) => p != null && '$p'.isNotEmpty)
                                .join(' • '),
                            Icons.public,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
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
    BuildContext context, {
    Map<String, dynamic>? guideData,
  }) {
    return GestureDetector(
      onTap: () {
        if (guideData != null) {
          context.push('/knowledge-base/detail', extra: guideData);
        } else {
          context.push(
            '/knowledge-base/detail',
            extra: {'title': title, 'category': tag},
          );
        }
      },
      child: Container(
        width: 200,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background Image
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GuideImage(guide: guideData ?? const {}),
            ),
            // Gradient Overlay
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
            if (guideData != null)
              Positioned(
                top: 4,
                right: 4,
                child: GuideBookmarkButton(guide: guideData),
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
          const Icon(Icons.open_in_new, color: Colors.grey, size: 20),
        ],
      ),
    );
  }
}
