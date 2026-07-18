import 'package:flutter/material.dart';
import '../models/track.dart';

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
        child: Image.network(
          track.coverUrl,
          width: dense ? 44 : 52,
          height: dense ? 44 : 52,
          fit: BoxFit.cover,
          // Without this, Flutter decodes the FULL original image into
          // memory (e.g. a 2000x2000 cover) just to show a 50px thumbnail.
          // Scrolling through hundreds/thousands of tracks like that is
          // exactly what eats RAM and can crash the app. Capping the
          // decode size to roughly what's actually on screen fixes it.
          cacheWidth: ((dense ? 44 : 52) * MediaQuery.of(context).devicePixelRatio).round(),
          errorBuilder: (_, __, ___) => Container(
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
