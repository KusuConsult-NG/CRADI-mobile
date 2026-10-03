/// Names the thumbnail that belongs beside a Supabase Storage image.
///
/// Supabase addresses an object by its path, and the path is a verbatim
/// suffix of the public URL, so the `_thumb.jpg` sibling is recoverable
/// from the URL alone and nothing has to be stored alongside the report.
/// Appwrite cannot do that — it addresses a file by a digest id — so it
/// derives a thumbnail's id from its photo's instead; see
/// `AppwriteDataBackend.thumbUrlFor`. Both sit behind
/// `DataBackend.thumbUrlFor`, which is what display code calls.
class ImageUrlResolver {
  ImageUrlResolver._();

  /// Marker that identifies a Supabase Storage *public* object URL. Only
  /// these carry a path this can read: any other host (an admin-set
  /// knowledge-base image on a third-party site, a data: URI, a local
  /// file path) has no sibling to name and is left alone.
  static const String supabasePublicMarker = '/storage/v1/object/public/';

  /// Object path (`<bucket>/<path>`) of a Supabase public storage URL, or
  /// null when [url] is not one. Never throws.
  static String? supabaseObjectPath(String url) {
    final marker = url.indexOf(supabasePublicMarker);
    if (marker < 0) return null;
    var path = url.substring(marker + supabasePublicMarker.length);
    // Drop any query/fragment (e.g. a `?t=` cache buster): the sibling is
    // named from the path alone.
    for (final sep in ['?', '#']) {
      final i = path.indexOf(sep);
      if (i >= 0) path = path.substring(0, i);
    }
    if (path.isEmpty) return null;
    return path;
  }

  /// Storage object path of the thumbnail stored next to [storagePath]:
  /// the same folder (so the uploader's user id stays the first segment,
  /// which is what storage RLS keys on) with `_thumb.jpg` appended to the
  /// object name.
  ///
  /// `uid/report_0_photo.jpg` -> `uid/report_0_photo_thumb.jpg`.
  static String thumbStoragePath(String storagePath) {
    final slash = storagePath.lastIndexOf('/');
    final name = storagePath.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    return '${storagePath.substring(0, slash + 1)}${stem}_thumb.jpg';
  }

  /// Public URL of the thumbnail belonging to the full-size image at [url],
  /// by the same `_thumb.jpg` convention, or null when [url] is not a
  /// Supabase public storage URL (so callers fall back to [url] itself).
  ///
  /// Reports uploaded before thumbnails existed have no such object; the
  /// request 404s and the image widget falls back to the full-size URL.
  static String? thumbUrlFor(String url) {
    final path = supabaseObjectPath(url);
    if (path == null || !path.contains('/')) return null;
    if (path.endsWith('_thumb.jpg')) return url;
    final marker = url.indexOf(supabasePublicMarker);
    final base = url.substring(0, marker + supabasePublicMarker.length);
    return '$base${thumbStoragePath(path)}';
  }
}
