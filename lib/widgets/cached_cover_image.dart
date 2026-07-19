import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/download_service.dart';

/// Drop-in replacement for `Image.network(track.coverUrl, ...)` that shows
/// the on-device cached copy of the cover (downloaded alongside the audio
/// when the track was cached — see [DownloadService]) when one exists,
/// and transparently falls back to a *disk-cached* network fetch
/// otherwise (via [CachedNetworkImageProvider]) — so scrolling past the
/// same covers again, even after restarting the app, doesn't re-download
/// them. Callers don't need to know which path was used.
class CachedCoverImage extends StatelessWidget {
  const CachedCoverImage({
    super.key,
    required this.track,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  final Track track;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext context)? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final localPath = context.watch<DownloadService>().coverPathFor(track.id);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = width != null ? (width! * dpr).round() : null;
    final cacheHeight = height != null ? (height! * dpr).round() : null;

    Widget fallback(BuildContext ctx) =>
        errorBuilder?.call(ctx) ??
        Container(
          width: width,
          height: height,
          color: Theme.of(ctx).cardColor,
          child: const Icon(Icons.music_note),
        );

    Widget networkImage() {
      ImageProvider provider = CachedNetworkImageProvider(track.coverUrl);
      // The raw Image() constructor (unlike Image.file/.network/.asset)
      // has no cacheWidth/cacheHeight shorthand — those named constructors
      // just wrap the provider in ResizeImage under the hood, so we do
      // the same thing manually here to get the same decode-size saving.
      if (cacheWidth != null || cacheHeight != null) {
        provider = ResizeImage(
          provider,
          width: cacheWidth,
          height: cacheHeight,
        );
      }
      return Image(
        image: provider,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (ctx, __, ___) => fallback(ctx),
      );
    }

    if (localPath != null) {
      return Image.file(
        File(localPath),
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        // A stale cached-cover reference (file removed outside the app,
        // e.g. system storage cleanup) shouldn't take the whole tile
        // down — just fall back to the network like an uncached track.
        errorBuilder: (_, __, ___) => networkImage(),
      );
    }

    return networkImage();
  }
}
