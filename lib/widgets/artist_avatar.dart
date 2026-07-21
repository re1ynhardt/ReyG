import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Circular avatar for an artist, used on [ArtistTracksScreen] and in the
/// "artists" block on the Search screen. [imageUrl] may be a network URL
/// or a local file path (a freshly picked image not yet round-tripped
/// through the backend) — same dual handling used for the account avatar
/// and playlist cover thumbnails elsewhere in the app. Falls back to a
/// generic person icon when [imageUrl] is empty (e.g. no developer-set
/// avatar and the artist has no tracks to fall back to).
class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({super.key, required this.imageUrl, this.radius = 28});

  final String imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ImageProvider? image = imageUrl.isEmpty
        ? null
        : (imageUrl.startsWith('http')
            ? CachedNetworkImageProvider(imageUrl)
            : FileImage(File(imageUrl)) as ImageProvider);
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).cardColor,
      backgroundImage: image,
      child: image == null
          ? Icon(Icons.person, size: radius, color: Theme.of(context).hintColor)
          : null,
    );
  }
}
