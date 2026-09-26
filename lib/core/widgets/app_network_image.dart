import 'package:cached_network_image/cached_network_image.dart';
import 'package:climate_app/core/utils/image_url_resolver.dart';
import 'package:flutter/material.dart';

/// The app's single point for showing a remote image.
///
/// Wraps [CachedNetworkImage] (so bytes are fetched once and then served
/// from the disk cache, including offline) and routes every URL through
/// [ImageUrlResolver.resolve], which is a no-op unless an ImageKit endpoint
/// is configured at build time.
///
/// [fallbackUrl] is loaded when [url] fails. That is what makes thumbnails
/// safe to derive by name: reports uploaded before thumbnails existed have
/// no `_thumb.jpg` object, so the 404 falls through to the full-size image.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fallbackUrl,
    this.width,
    this.height,
    this.fit,
    this.renderWidth,
    this.renderQuality,
    this.placeholder,
    this.progressIndicatorBuilder,
    this.errorWidget,
  });

  /// Shows the small thumbnail stored next to [url] (see
  /// [ImageUrlResolver.thumbUrlFor]) and falls back to [url] itself when
  /// there is none. [renderWidth] additionally asks ImageKit, when it is
  /// configured, to render at that width — which also shrinks the fallback
  /// for reports that never got a thumbnail.
  factory AppNetworkImage.thumbnail({
    Key? key,
    required String url,
    double? width,
    double? height,
    BoxFit? fit,
    int renderWidth = 320,
    int renderQuality = 70,
    WidgetBuilder? placeholder,
    WidgetBuilder? errorWidget,
  }) {
    final thumb = ImageUrlResolver.thumbUrlFor(url);
    return AppNetworkImage(
      key: key,
      url: thumb ?? url,
      fallbackUrl: thumb == null || thumb == url ? null : url,
      width: width,
      height: height,
      fit: fit,
      renderWidth: renderWidth,
      renderQuality: renderQuality,
      placeholder: placeholder,
      errorWidget: errorWidget,
    );
  }

  final String url;
  final String? fallbackUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;

  /// Width, in pixels, to ask the CDN to render at. Ignored when no ImageKit
  /// endpoint is configured.
  final int? renderWidth;
  final int? renderQuality;

  final WidgetBuilder? placeholder;

  /// Determinate loading indicator, for the few places that showed one with
  /// `Image.network`'s `loadingBuilder`. Mutually exclusive with
  /// [placeholder].
  final Widget Function(BuildContext, DownloadProgress)?
  progressIndicatorBuilder;

  final WidgetBuilder? errorWidget;

  @override
  Widget build(BuildContext context) {
    final fallback = fallbackUrl;
    return _image(
      context,
      url,
      onError: fallback == null
          ? null
          : (context) => _image(context, fallback, onError: null),
    );
  }

  Widget _image(
    BuildContext context,
    String rawUrl, {
    required WidgetBuilder? onError,
  }) {
    return CachedNetworkImage(
      imageUrl: ImageUrlResolver.resolve(
        rawUrl,
        width: renderWidth,
        quality: renderQuality,
      ),
      width: width,
      height: height,
      fit: fit,
      placeholder: placeholder == null
          ? null
          : (context, _) => placeholder!(context),
      progressIndicatorBuilder: progressIndicatorBuilder == null
          ? null
          : (context, _, progress) =>
                progressIndicatorBuilder!(context, progress),
      errorWidget: (context, _, _) =>
          (onError ?? errorWidget)?.call(context) ?? const SizedBox.shrink(),
    );
  }
}
