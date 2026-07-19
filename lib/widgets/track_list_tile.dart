import 'package:flutter/material.dart';
import '../models/track.dart';
import 'cached_cover_image.dart';

class TrackListTile extends StatelessWidget {
  const TrackListTile({
    super.key,
    required this.track,
    required this.onTap,
    this.trailing,
    this.isPlaying = false,
    this.dense = false,
  });

  final Track track;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool isPlaying;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.symmetric(horizontal: dense ? 8 : 16, vertical: 0),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedCoverImage(
          track: track,
          width: dense ? 44 : 52,
          height: dense ? 44 : 52,
          errorBuilder: (context) => Container(
            width: dense ? 44 : 52,
            height: dense ? 44 : 52,
            color: Theme.of(context).cardColor,
            child: const Icon(Icons.music_note),
          ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isPlaying ? accent : null,
        ),
      ),
      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
    );
  }
}
