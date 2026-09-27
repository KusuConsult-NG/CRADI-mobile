import 'package:climate_app/core/constants/app_config.dart';

/// Rewrites image URLs for delivery.
///
/// Two independent jobs, both pure:
///
/// 1. [thumbUrlFor] / [thumbStoragePath] derive the name of the small
///    thumbnail uploaded next to a report photo (see
///    `ReportingProvider`). Thumbnails are derived by convention rather than
///    stored in a column, so nothing new has to be persisted and the
///    existing `reports.image_urls` immutability guard covers them too.
///
/// 2. [resolve] optionally routes a Supabase Storage public URL through an
///    ImageKit URL endpoint (a CDN in front of the bucket) and can ask
///    ImageKit for a smaller render. Disabled — every URL is returned
///    unchanged — unless `IMAGEKIT_URL_ENDPOINT` is defined at build time.
///
/// ImageKit URL form (verified against ImageKit's docs, see
/// integration/configure-origin/s3-compatible-external-storages.md in
/// github.com/imagekitio/docs-keep-a-changelog): with a storage origin
/// attached to a URL endpoint, a file served by the origin at
/// `<origin>/rest-of-the-path.jpg` is served by ImageKit at
/// `https://ik.imagekit.io/<imagekit_id>/rest-of-the-path.jpg`, and
/// transformations go either in a `tr:` path segment
/// (`.../tr:w-300,h-300/rest-of-the-path.jpg`) or in a `tr` query parameter
/// (`...rest-of-the-path.jpg?tr=w-300,h-300`). The query form is used here so
/// the object path stays a verbatim suffix of the URL.
///
/// The endpoint is expected to have a *web server / storage* origin pointing
/// at this project's Supabase Storage public base
/// (`https://<ref>.supabase.co/storage/v1/object/public/`), so the path
/// ImageKit receives is `<bucket>/<object path>`.
class ImageUrlResolver {
  ImageUrlResolver._();

  /// Marker that identifies a Supabase Storage *public* object URL. Only
  /// these are rewritten: the ImageKit endpoint's origin is this project's
  /// bucket, so any other host (an admin-set knowledge-base image on a
  /// third-party site, a data: URI, a local file path) is left alone.
  static const String supabasePublicMarker = '/storage/v1/object/public/';

  /// Object path (`<bucket>/<path>`) of a Supabase public storage URL, or
  /// null when [url] is not one. Never throws.
  static String? supabaseObjectPath(String url) {
    final marker = url.indexOf(supabasePublicMarker);
    if (marker < 0) return null;
    var path = url.substring(marker + supabasePublicMarker.length);
    // Drop any query/fragment (e.g. a `?t=` cache buster): ImageKit keys on
    // the path and `tr` is added below.
    for (final sep in ['?', '#']) {
      final i = path.indexOf(sep);
      if (i >= 0) path = path.substring(0, i);
    }
    if (path.isEmpty) return null;
    return path;
  }

  /// [url] rewritten to be served through ImageKit, optionally asking for a
  /// [width]-wide render at [quality].
  ///
  /// Returns [url] unchanged when no endpoint is configured, when [url] is
  /// not a Supabase public storage URL, or when it is empty/malformed. Never
  /// throws.
  static String resolve(
    String url, {
    int? width,
    int? quality,
    String? endpoint,
  }) {
    final base = (endpoint ?? AppConfig.imageKitUrlEndpoint).trim();
    if (base.isEmpty || url.isEmpty) return url;
    final path = supabaseObjectPath(url);
    if (path == null) return url;

    final transformations = <String>[
      if (width != null && width > 0) 'w-$width',
      if (quality != null && quality > 0) 'q-$quality',
    ];
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final rewritten = '$root/$path';
    if (transformations.isEmpty) return rewritten;
    return '$rewritten?tr=${transformations.join(',')}';
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
