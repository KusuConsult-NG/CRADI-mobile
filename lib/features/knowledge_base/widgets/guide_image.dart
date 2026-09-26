import 'package:cached_network_image/cached_network_image.dart';
import 'package:climate_app/features/knowledge_base/knowledge_categories.dart';
import 'package:flutter/material.dart';

/// The guide's admin-supplied image URL, or null when it has none (or the
/// value is not an http(s) URL).
String? guideImageUrl(Map<String, dynamic> guide) {
  final url = guide['imageUrl']?.toString().trim() ?? '';
  return url.startsWith('http') ? url : null;
}

/// Cover image of a knowledge-base guide: the admin-supplied image when the
/// guide has one, otherwise (and when it fails to load) a local placeholder
/// drawn with the guide's category icon and color. No third-party image is
/// ever substituted.
class GuideImage extends StatelessWidget {
  const GuideImage({super.key, required this.guide});

  final Map<String, dynamic> guide;

  @override
  Widget build(BuildContext context) {
    final url = guideImageUrl(guide);
    if (url == null) return GuideImagePlaceholder(guide: guide);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (context, url) => GuideImagePlaceholder(guide: guide),
      errorWidget: (context, url, error) => GuideImagePlaceholder(guide: guide),
    );
  }
}

/// Category-colored panel with the category icon (see
/// [knowledgeCategoryFor]); a neutral book icon for unknown categories.
class GuideImagePlaceholder extends StatelessWidget {
  const GuideImagePlaceholder({super.key, required this.guide});

  final Map<String, dynamic> guide;

  @override
  Widget build(BuildContext context) {
    final category =
        knowledgeCategoryFor(guide['hazardType']) ??
        knowledgeCategoryFor(guide['category']);
    final color = category?.color ?? Colors.blueGrey;
    final icon = category?.icon ?? Icons.menu_book_outlined;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.15)!,
            Color.lerp(color, Colors.black, 0.35)!,
          ],
        ),
      ),
      alignment: const Alignment(0, -0.35),
      child: Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 44),
    );
  }
}
