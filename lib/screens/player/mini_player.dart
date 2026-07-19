import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/player_provider.dart';
import 'now_playing_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final duration = player.duration ?? track.duration;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (player.position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierColor: Colors.transparent,
          // Kept short and snappy on purpose — a long, softly-eased
          // transition reads as "cheap" here. Quick deceleration in,
          // quick acceleration out.
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, __, ___) => const NowPlayingScreen(),
          transitionsBuilder: (_, animation, __, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutExpo,
              reverseCurve: Curves.easeInExpo,
            );
            final slide = Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved);
            // Blur is strongest at the start/end of the transition and
            // resolves to 0 once the sheet is fully open — gives the
            // open/close motion some weight instead of a plain slide.
            final blurSigma = Tween<double>(begin: 16, end: 0).animate(curved);

            return SlideTransition(
              position: slide,
              child: AnimatedBuilder(
                animation: blurSigma,
                builder: (context, blurredChild) => ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: blurSigma.value,
                    sigmaY: blurSigma.value,
                    tileMode: TileMode.decal,
                  ),
                  child: blurredChild,
                ),
                child: child,
              ),
            );
          },
        ),
      ),
      child: Container(
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Cover art blown up to fill the whole bar — this is the layer
            // BackdropFilter below blurs, giving the bar a soft glow/gradient
            // tinted by the track's own artwork.
            Positioned.fill(
              child: Image.network(
                track.coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: Theme.of(context).cardColor),
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30, tileMode: TileMode.mirror),
                // Tint so text/icons stay legible over whatever colors the
                // blurred art produced, while still letting them show through.
                child: Container(color: Theme.of(context).cardColor.withOpacity(0.55)),
              ),
            ),
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Image.network(
                            track.coverUrl,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            cacheWidth: (40 * MediaQuery.of(context).devicePixelRatio).round(),
                            errorBuilder: (_, __, ___) => Container(
                              width: 40,
                              height: 40,
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: const Icon(Icons.music_note, size: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text(track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          onPressed: player.togglePlayPause,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: player.next,
                        ),
                      ],
                    ),
                  ),
                ),
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.secondary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
