import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  // Drag-to-dismiss state. _dragExtent is how far (in px) the sheet has
  // been pulled down; the snap-back animation reuses the same field so
  // the gesture and the animation drive the same value.
  late final AnimationController _snapBackController;
  double _dragExtent = 0;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _snapBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _snapBackController.dispose();
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_dismissing) return;
    if (_snapBackController.isAnimating) _snapBackController.stop();
    setState(() {
      _dragExtent = (_dragExtent + details.primaryDelta!).clamp(0.0, double.infinity);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dismissing) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final velocity = details.primaryVelocity ?? 0;
    final shouldDismiss = _dragExtent > screenHeight * 0.25 || velocity > 800;

    if (shouldDismiss) {
      setState(() => _dismissing = true);
      Navigator.of(context).maybePop();
      return;
    }

    final snapBack = Tween<double>(begin: _dragExtent, end: 0).animate(
      CurvedAnimation(parent: _snapBackController, curve: Curves.easeOutCubic),
    );
    void listener() => setState(() => _dragExtent = snapBack.value);
    snapBack.addListener(listener);
    _snapBackController.forward(from: 0).whenCompleteOrCancel(() {
      snapBack.removeListener(listener);
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Just the sharp cover now — the glow moved to a full-screen ambient
  /// background (see [_buildAmbientBackground]) so it can be large
  /// enough to reach the top of the screen without reading as a small
  /// blurred circle sitting behind the art.
  Widget _buildCover(BuildContext context, String trackId, String coverUrl) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final dpr = MediaQuery.of(context).devicePixelRatio;
        return Hero(
          tag: 'cover_$trackId',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              coverUrl,
              fit: BoxFit.cover,
              width: w,
              height: h,
              // Only one of these is on screen at a time, but
              // uploaded covers can be large — cap decoding so a
              // 3000x3000 cover doesn't get fully decoded just to
              // fill a phone-width box.
              cacheWidth: (w * dpr).round(),
              errorBuilder: (_, __, ___) => Container(
                color: Theme.of(context).cardColor,
                child: const Icon(Icons.music_note, size: 80),
              ),
            ),
          ),
        );
      },
    );
  }

  /// A big, blurred copy of the cover filling the whole screen behind
  /// everything else — including the header — so the glow reads as an
  /// ambient wash reaching the very top of the screen instead of a
  /// small halo with a visible (roughly circular) edge around the art.
  Widget _buildAmbientBackground(BuildContext context, String coverUrl) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.55,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90, tileMode: TileMode.decal),
          child: Image.network(
            coverUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
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
    final screenHeight = MediaQuery.of(context).size.height;
    final dragProgress = (_dragExtent / screenHeight).clamp(0.0, 1.0);

    final content = Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _buildAmbientBackground(context, track.coverUrl)),
          SafeArea(
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
                    child: _buildCover(context, track.id, track.coverUrl),
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
        ],
      ),
    );

    return GestureDetector(
      // Only the vertical drag is used for dismissal — horizontal
      // gestures (e.g. the slider) pass straight through.
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: Opacity(
        opacity: 1 - dragProgress * 0.5,
        child: Transform.translate(
          offset: Offset(0, _dragExtent),
          child: content,
        ),
      ),
    );
  }
}
