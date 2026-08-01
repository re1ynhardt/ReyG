import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../providers/player_provider.dart';
import '../../widgets/cached_cover_image.dart';
import 'now_playing_screen.dart';

/// Persistent bottom bar — mounted on (almost) every screen, so anything
/// expensive here is paid on every frame of every scroll in the app.
///
/// PERF NOTE: playback position ticks via [PlayerProvider.notifyListeners]
/// several times a second. The old version called `context.watch<PlayerProvider>()`
/// at the top of build(), so the *entire* bar — including the cover art and
/// the `BackdropFilter` blur behind it — was rebuilt and re-blurred on every
/// tick, even though only the thin progress line actually changes that
/// often. `BackdropFilter` is one of the most expensive widgets in Flutter
/// (it forces a `saveLayer` + GPU blur of whatever's behind it), so doing
/// that continuously while the person scrolls a list underneath it is the
/// single biggest cause of the jank.
///
/// Fix: split the bar into pieces scoped to what they actually need via
/// `context.select`, so only the progress line rebuilds on each tick —
/// the cover/blur/buttons only rebuild when the track or transport state
/// actually changes.
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
    // Only rebuilds when the *track itself* changes (new/cleared track) —
    // not on position/duration ticks, since PlayerProvider only reassigns
    // this field from the currentIndexStream listener. This is the one
    // watch this widget needs at this level.
    final track = context.select<PlayerProvider, Track?>((p) => p.currentTrack);
    if (track == null || track.id == _dismissingTrackId) return const SizedBox.shrink();

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
        context.read<PlayerProvider>().stopAndDismiss();
      },
      background: _buildSwipeBackground(context, Alignment.centerLeft),
      secondaryBackground: _buildSwipeBackground(context, Alignment.centerRight),
      child: _MiniPlayerContent(track: track),
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
}

/// Everything that only depends on *which track* is playing — cover art,
/// the blurred backdrop behind it, title/artist text, and the transport
/// buttons. None of this needs to know about playback position, so none
/// of it should rebuild on position ticks.
class _MiniPlayerContent extends StatelessWidget {
  const _MiniPlayerContent({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
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
            // Cover art + its BackdropFilter blur, isolated in their own
            // RepaintBoundary. This subtree is rebuilt only when the
            // track changes (see _MiniPlayerContent scope above), so the
            // RepaintBoundary lets the engine reuse the already-rasterized
            // blurred layer on every other frame — including the ~5x/sec
            // frames where only the progress line below changes — instead
            // of re-running the (expensive) blur.
            RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Cover art blown up to fill the whole bar — this is the
                  // layer BackdropFilter below blurs, giving the bar a soft
                  // glow/gradient tinted by the track's own artwork.
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
                      // Tint so text/icons stay legible over whatever colors
                      // the blurred art produced, while still letting them
                      // show through.
                      child: Container(color: Theme.of(context).cardColor.withOpacity(0.55)),
                    ),
                  ),
                ],
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
                        const _MiniPlayerButtons(),
                      ],
                    ),
                  ),
                ),
                _MiniPlayerProgressBar(fallbackDuration: track.duration),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Transport controls. Reads playback methods once via `context.read`
/// (they're stable function references, no need to watch for those) and
/// only *watches* the small bits of state that affect how the buttons
/// look (`isPlaying`, repeat mode) — both of which change rarely (user
/// taps), unlike position.
class _MiniPlayerButtons extends StatelessWidget {
  const _MiniPlayerButtons();

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();
    final isPlaying = context.select<PlayerProvider, bool>((p) => p.isPlaying);
    final isRepeatOn = context.select<PlayerProvider, bool>((p) => p.isRepeatOn);
    final isRepeatOne = context.select<PlayerProvider, bool>((p) => p.isRepeatOne);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
          icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
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
          icon: Icon(isRepeatOne ? Icons.repeat_one_rounded : Icons.repeat_rounded),
          color: isRepeatOn ? Theme.of(context).colorScheme.secondary : Theme.of(context).hintColor,
          onPressed: player.toggleRepeat,
        ),
      ],
    );
  }
}

/// The ONLY part of the mini player that's meant to rebuild on every
/// position tick. Isolated into its own tiny (2px-tall) widget so the
/// cover/blur/buttons above never have to repaint just because playback
/// moved forward a fraction of a second.
class _MiniPlayerProgressBar extends StatelessWidget {
  const _MiniPlayerProgressBar({required this.fallbackDuration});

  final Duration fallbackDuration;

  @override
  Widget build(BuildContext context) {
    // A single `select` with a computed value: this widget only rebuilds
    // when the *resulting ratio* changes, not on every raw position or
    // duration update individually.
    final progress = context.select<PlayerProvider, double>((p) {
      final duration = p.duration ?? fallbackDuration;
      if (duration.inMilliseconds == 0) return 0.0;
      return (p.position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    });

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 2,
        backgroundColor: Colors.transparent,
        valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.secondary),
      ),
    );
  }
}
