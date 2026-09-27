import 'package:climate_app/core/l10n/l10n.dart';
import 'package:climate_app/features/knowledge_base/guide_bookmarks.dart';
import 'package:flutter/material.dart';

/// Save / unsave control for a knowledge-base guide, drawn over a guide
/// card's image.
///
/// It shows the real state from [GuideBookmarks] and toggles it, so the
/// icon is never a decoration that merely looks like a control. Guides with
/// neither an id nor a title cannot be saved and render nothing.
class GuideBookmarkButton extends StatelessWidget {
  const GuideBookmarkButton({super.key, required this.guide, this.size = 16});

  final Map<String, dynamic> guide;

  /// Icon size; the tap target is padded out to 40pt around it.
  final double size;

  @override
  Widget build(BuildContext context) {
    final id = GuideBookmarks.idFor(guide);
    if (id.isEmpty) return const SizedBox.shrink();
    final bookmarks = GuideBookmarks();
    return ValueListenableBuilder<Set<String>>(
      valueListenable: bookmarks.ids,
      builder: (context, ids, _) {
        final saved = ids.contains(id);
        final label = saved
            ? context.l10n.knowledgeBookmarkRemoveTooltip
            : context.l10n.knowledgeBookmarkAddTooltip;
        return Semantics(
          button: true,
          toggled: saved,
          label: label,
          child: Tooltip(
            message: label,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                final nowSaved = await bookmarks.toggle(id);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      nowSaved
                          ? context.l10n.knowledgeBookmarked
                          : context.l10n.knowledgeBookmarkRemoved,
                    ),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: ExcludeSemantics(
                      child: Icon(
                        saved ? Icons.bookmark : Icons.bookmark_border,
                        color: Colors.white,
                        size: size,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
