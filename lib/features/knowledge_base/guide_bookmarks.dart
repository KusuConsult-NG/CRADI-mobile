import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The single source of truth for saved (bookmarked) knowledge-base guides.
///
/// The list lives in SharedPreferences under [storageKey]; every screen reads
/// and writes it through this service and rebuilds from [ids], so the detail
/// screen's bookmark button, the featured cards on the knowledge base screen
/// and the "Saved" filter on the guides list can never disagree.
class GuideBookmarks {
  GuideBookmarks._internal();
  static final GuideBookmarks _instance = GuideBookmarks._internal();
  factory GuideBookmarks() => _instance;

  /// SharedPreferences key holding the saved guide ids.
  static const String storageKey = 'bookmarked_guides';

  /// The saved guide ids. Listenable so widgets rebuild on a toggle made
  /// anywhere else in the app.
  final ValueNotifier<Set<String>> ids = ValueNotifier<Set<String>>(const {});

  /// Whether the stored ids have been read. No pending future is cached:
  /// a read that never completes (a torn-down platform channel) must not
  /// be able to block a later save.
  bool _loaded = false;

  /// Stable id of [guide]: the database row id, or the title for the
  /// bundled offline guides, which have no id.
  static String idFor(Map<String, dynamic> guide) {
    final id = guide['id']?.toString().trim() ?? '';
    if (id.isNotEmpty) return id;
    return guide['title']?.toString().trim() ?? '';
  }

  /// Reads the saved ids from storage once. Safe to call from every screen
  /// that shows bookmarks; later calls are no-ops.
  Future<void> load() async {
    if (_loaded) return;
    final stored = await _read();
    if (stored != null) ids.value = stored;
  }

  Future<Set<String>?> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _loaded = true;
      return (prefs.getStringList(storageKey) ?? const <String>[]).toSet();
    } on Object catch (_) {
      // Storage unavailable: behave as "nothing saved" rather than throw.
      return null;
    }
  }

  bool contains(String id) => id.isNotEmpty && ids.value.contains(id);

  bool isBookmarked(Map<String, dynamic> guide) => contains(idFor(guide));

  /// Adds or removes [id]; returns whether it is saved afterwards. A guide
  /// with no id at all (neither row id nor title) cannot be saved.
  Future<bool> toggle(String id) async {
    if (id.isEmpty) return false;
    // Re-read rather than trust the cache: another isolate or an earlier
    // run may have written since, and this is the only writer.
    final next = (await _read() ?? ids.value).toSet();
    final saved = !next.remove(id);
    if (saved) next.add(id);
    ids.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(storageKey, next.toList());
    } on Object catch (_) {
      // The in-memory state stands; it is re-read on the next cold start.
    }
    return saved;
  }

  /// The saved guides among [guides], in the order they were given.
  List<Map<String, dynamic>> filter(List<Map<String, dynamic>> guides) =>
      guides.where(isBookmarked).toList();

  @visibleForTesting
  void resetForTesting() {
    _loaded = false;
    ids.value = const {};
  }
}
