import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../providers/player_provider.dart';
import '../../widgets/cached_cover_image.dart';
import 'now_playing_screen.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  /// Id of the track whose mini player we've just swiped away locally.
  /// Flutter requires a dismissed Dismissible to be removed from the tree
  /// synchronously inside onDismissed — relying on PlayerProvider's async
  /// stopAndDismiss()/notifyListeners() to clear currentTrack was a frame
  /// too late, which is exactly what threw "still part of the tree".
  /// Tracking it locally with setState (the pattern Flutter's own docs
  /// use for Dismissible) removes it immediately, in the same callback.
  String? _dismissingTrackId;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;
    if (track == null || track.id == _dismissingTrackId) return const SizedBox.shrink();

    final duration = player.duration ?? track.duration;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (player.position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return Dismissible(
      // Keyed by track id so Flutter treats a new track as a fresh widget
      // instead of trying to animate/reuse the just-dismissed one.
      key: ValueKey('mini_player_${track.id}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        setState(() => _dismissingTrackId = track.id);
        // Fire-and-forget: the mini player is already gone from the tree
        // via the setState above, so this doesn't need to be awaited or
        // ordered relative to anything UI-related.
        player.stopAndDismiss();
      },
      background: _buildSwipeBackground(context, Alignment.centerLeft),
      secondaryBackground: _buildSwipeBackground(context, Alignment.centerRight),
      child: _buildContent(context, player, track, progress),
    );
  }

  /// Red "stop" hint revealed behind the mini player as it's swiped away.
  Widget _buildSwipeBackground(BuildContext context, Alignment alignment) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignment,
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.stop_circle_rounded, color: Colors.white),
    );
  }

  Widget _buildContent(BuildContext context, PlayerProvider player, Track track, double progress) {
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
              child: CachedCoverImage(
                track: track,
                fit: BoxFit.cover,
                errorBuilder: (context) => Container(color: Theme.of(context).cardColor),
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
                          child: CachedCoverImage(
                            track: track,
                            width: 40,
                            height: 40,
                            errorBuilder: (context) => Container(
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
                          iconSize: 22,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: player.previous,
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          icon: Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          onPressed: player.togglePlayPause,
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          iconSize: 22,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: player.next,
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: Icon(player.isRepeatOne ? Icons.repeat_one_rounded : Icons.repeat_rounded),
                          color: player.isRepeatOn
                              ? Theme.of(context).colorScheme.secondary
                              : Theme.of(context).hintColor,
                          onPressed: player.toggleRepeat,
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
