import 'package:climate_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:climate_app/core/services/tts_service.dart';
import 'package:climate_app/features/knowledge_base/providers/knowledge_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KnowledgeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> guide;

  const KnowledgeDetailScreen({super.key, required this.guide});

  @override
  State<KnowledgeDetailScreen> createState() => _KnowledgeDetailScreenState();
}

class _KnowledgeDetailScreenState extends State<KnowledgeDetailScreen> {
  bool _isBookmarked = false;
  static const _bookmarksKey = 'bookmarked_guides';

  @override
  void initState() {
    super.initState();
    _loadBookmarkState();
  }

  String get _guideId =>
      widget.guide['id']?.toString() ?? widget.guide['title']?.toString() ?? '';

  Future<void> _loadBookmarkState() async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarks = prefs.getStringList(_bookmarksKey) ?? [];
    if (mounted) {
      setState(() => _isBookmarked = bookmarks.contains(_guideId));
    }
  }

  Future<void> _toggleBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    final bookmarks = prefs.getStringList(_bookmarksKey) ?? [];
    if (_isBookmarked) {
      bookmarks.remove(_guideId);
    } else {
      bookmarks.add(_guideId);
    }
    await prefs.setStringList(_bookmarksKey, bookmarks);
    if (mounted) {
      setState(() => _isBookmarked = !_isBookmarked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isBookmarked ? 'Guide bookmarked' : 'Bookmark removed',
          ),
          duration: const Duration(seconds: 1),
          backgroundColor: _isBookmarked
              ? AppColors.successGreen
              : AppColors.textSecondary,
        ),
      );
    }
  }

  void _shareGuide() {
    final title = widget.guide['title'] ?? 'CRADI Guide';
    final description = widget.guide['description'] ?? '';
    final content = widget.guide['content'] ?? '';
    final shareText =
        '$title\n\n$description${content.isNotEmpty ? '\n\n$content' : ''}\n\nShared via CRADI Early Warning App';
    SharePlus.instance.share(ShareParams(text: shareText));
  }

  @override
  Widget build(BuildContext context) {
    final guide = widget.guide;
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
            onPressed: _shareGuide,
          ),
          IconButton(
            icon: Icon(
              _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: _isBookmarked
                  ? AppColors.primaryRed
                  : AppColors.textPrimary,
            ),
            onPressed: _toggleBookmark,
          ),
          IconButton(
            icon: const Icon(
              Icons.volume_up_outlined,
              color: AppColors.textPrimary,
            ),
            onPressed: () async {
              try {
                final text =
                    guide['content'] ?? guide['description'] ?? guide['title'];
                if (text != null && text.isNotEmpty) {
                  await TTSService().speak(text);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No text to speak')),
                  );
                }
              } on Exception {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Text-to-speech is unavailable. Please try again.',
                      ),
                    ),
                  );
                }
              }
            },
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
            if (guide['imageUrl'] != null &&
                guide['imageUrl'].toString().isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    guide['imageUrl'],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildFallbackImage(categoryIcon, categoryColor);
                    },
                  ),
                ),
              )
            else
              _buildFallbackImage(categoryIcon, categoryColor),
            const SizedBox(height: 24),
            if (guide['content'] != null &&
                guide['content'].toString().isNotEmpty)
              _buildDynamicContent(guide['content'])
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.menu_book,
                        size: 48,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Detailed content coming soon.',
                        style: GoogleFonts.lexend(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
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
            Consumer<KnowledgeProvider>(
              builder: (context, knowledgeProvider, child) {
                // Find guides with the same category/tag
                final currentCategory =
                    guide['category'] ?? guide['hazardType'] ?? 'General';
                final relatedGuides = knowledgeProvider.guides
                    .where((g) {
                      final cat = g['category'] ?? g['hazardType'] ?? 'General';
                      // Ignore exact same guide
                      if (g['title'] == guide['title']) return false;
                      return cat.toString().toLowerCase() ==
                          currentCategory.toString().toLowerCase();
                    })
                    .take(3)
                    .toList();

                if (relatedGuides.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No related topics found.',
                      style: GoogleFonts.lexend(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  );
                }

                return Column(
                  children: relatedGuides.map((relatedGuide) {
                    return _buildRelatedItem(
                      relatedGuide['title'] ?? 'Guide',
                      categoryIcon,
                      onTap: () {
                        context.push(
                          '/knowledge-base/detail',
                          extra: relatedGuide,
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicContent(String content) {
    // Simple parser for **bold** and • bullets
    final sections = content.split('\n\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections.map((section) {
        // Filter out stray markdown formatting artifacts
        if (section.trim().toLowerCase() == 'copy code') {
          return const SizedBox.shrink();
        }

        if (section.startsWith('**')) {
          // Header style for bold lines
          return Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 8),
            child: Text(
              section.replaceAll('**', '').replaceAll(':', ''),
              style: GoogleFonts.lexend(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          );
        } else {
          // Regular text
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              section,
              style: GoogleFonts.lexend(
                fontSize: 16,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
          );
        }
      }).toList(),
    );
  }

  Widget _buildFallbackImage(IconData icon, Color color) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, size: 80, color: color.withValues(alpha: 0.3)),
    );
  }

  Widget _buildRelatedItem(String title, IconData icon, {VoidCallback? onTap}) {
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
        onTap: onTap,
      ),
    );
  }
}
