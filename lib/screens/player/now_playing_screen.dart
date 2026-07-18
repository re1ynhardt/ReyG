import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final library = context.watch<LibraryProvider>();
    final track = player.currentTrack;
    final accent = Theme.of(context).colorScheme.secondary;

    if (track == null) {
      return const Scaffold(body: Center(child: Text('—')));
    }

    final duration = player.duration ?? track.duration;
    final position = player.position > duration ? duration : player.position;
    final isFav = library.isFavorite(track.id);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(context.tr('now_playing'),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Hero(
                  tag: 'cover_${track.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      track.coverUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => Container(
                        color: Theme.of(context).cardColor,
                        child: const Icon(Icons.music_note, size: 80),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, color: Theme.of(context).hintColor)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? accent : null,
                    ),
                    onPressed: () => library.toggleFavorite(track.id),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  min: 0,
                  max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                  value: position.inMilliseconds.toDouble().clamp(0, duration.inMilliseconds.toDouble()),
                  onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmt(position), style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                    Text(_fmt(duration), style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 22,
                    icon: Icon(player.isRepeatOne ? Icons.repeat_one_rounded : Icons.repeat_rounded),
                    color: player.isRepeatOn ? accent : Theme.of(context).hintColor,
                    onPressed: player.toggleRepeat,
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_previous_rounded),
                    onPressed: player.previous,
                  ),
                  GestureDetector(
                    onTap: player.togglePlayPause,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 40,
                        color: Theme.of(context).scaffoldBackgroundColor,
                      ),
                    ),
                  ),
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: player.next,
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
