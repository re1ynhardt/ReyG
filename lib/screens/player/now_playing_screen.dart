import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/cached_cover_image.dart';
import '../../models/track.dart';
import '../library/playlist_picker_sheet.dart';
import '../library/artist_tracks_screen.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  // Vertical drag state, shared by both gestures this screen supports:
  // dragging down dismisses back to the mini player, dragging up opens
  // the artist's full track list. _dragExtent is how far (in px) the
  // sheet has been dragged — positive while dragging down, negative
  // while dragging up — and doubles as the value the snap-back
  // animation drives when a drag doesn't cross either threshold.
  late final AnimationController _snapBackController;
  double _dragExtent = 0;
  bool _dismissing = false;
  bool _openingArtist = false;

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
    if (_dismissing || _openingArtist) return;
    if (_snapBackController.isAnimating) _snapBackController.stop();
    setState(() {
      // Unclamped: positive extends downward (dismiss), negative
      // extends upward (open artist tracks) — same field drives the
      // Transform.translate for both directions.
      _dragExtent += details.primaryDelta!;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dismissing || _openingArtist) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final velocity = details.primaryVelocity ?? 0;

    final shouldDismiss = _dragExtent > screenHeight * 0.25 || velocity > 800;
    final shouldOpenArtist = _dragExtent < -screenHeight * 0.18 || velocity < -800;

    if (shouldDismiss) {
      setState(() => _dismissing = true);
      Navigator.of(context).maybePop();
      return;
    }

    if (shouldOpenArtist) {
      setState(() => _openingArtist = true);
      final track = context.read<PlayerProvider>().currentTrack;
      if (track != null) {
        _openArtistTracks(context, track.artist).whenComplete(() {
          if (!mounted) return;
          setState(() {
            _openingArtist = false;
            _dragExtent = 0;
          });
        });
      } else {
        setState(() {
          _openingArtist = false;
          _dragExtent = 0;
        });
      }
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

  /// Pushes [ArtistTracksScreen], sliding up from the bottom to match the
  /// swipe-up gesture that triggers it.
  Future<void> _openArtistTracks(BuildContext context, String artist) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (_, __, ___) => ArtistTracksScreen(artist: artist),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  void _showTrackMenu(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => PlaylistPickerSheet(track: track),
    );
  }

  /// Opens the lyrics panel as a translucent card anchored to the top-right
  /// corner (where the lyrics button lives), scaling/fading in from that
  /// corner rather than sliding up from the bottom like a sheet.
  void _showLyricsPanel(BuildContext context, Track track) {
    // barrierLabel is evaluated here, inside the button's onPressed
    // handler — NOT during a widget build — so it must use a
    // non-listening lookup. context.tr() calls Provider.of(listen:
    // true), which only works during build() and throws
    // "Tried to listen to a value... from outside of the widget tree"
    // when called from an event handler like this one.
    final label = AppStrings.t(context.read<AppState>().locale, 'lyrics');
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: label,
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim1, anim2) => _LyricsPanel(track: track),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            alignment: Alignment.topRight,
            scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
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
  Widget _buildCover(BuildContext context, Track track) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Hero(
          tag: 'cover_${track.id}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            // Only one of these is on screen at a time, but uploaded
            // covers can be large — CachedCoverImage caps decoding so a
            // 3000x3000 cover doesn't get fully decoded just to fill a
            // phone-width box.
            child: CachedCoverImage(
              track: track,
              width: w,
              height: h,
              errorBuilder: (context) => Container(
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
  Widget _buildAmbientBackground(BuildContext context, Track track) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.55,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90, tileMode: TileMode.decal),
            child: CachedCoverImage(
              track: track,
              errorBuilder: (_) => const SizedBox.shrink(),
            ),
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
    final dragProgress = (_dragExtent.abs() / screenHeight).clamp(0.0, 1.0);

    final content = Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _buildAmbientBackground(context, track)),
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
                    child: _buildCover(context, track),
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
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _openArtistTracks(context, track.artist),
                              child: Text(track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 15, color: Theme.of(context).hintColor)),
                            ),
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
                    children: [
                      IconButton(
                        iconSize: 24,
                        icon: const Icon(Icons.more_vert_rounded),
                        color: Theme.of(context).hintColor,
                        onPressed: () => _showTrackMenu(context, track),
                      ),
                      Expanded(
                        child: Row(
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
                      ),
                      // Balances the leading icon button visually while
                      // doubling as the lyrics entry point — same row/level
                      // as the more-vert menu and playback controls.
                      IconButton(
                        iconSize: 24,
                        icon: const Icon(Icons.title_rounded),
                        color: Theme.of(context).hintColor,
                        tooltip: context.tr('lyrics'),
                        onPressed: () => _showLyricsPanel(context, track),
                      ),
                    ],
                  ),
                  const SizedBox(height: 64),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      // Vertical drag only — down dismisses back to the mini player, up
      // opens the artist's tracks. Horizontal gestures (e.g. the
      // slider) pass straight through untouched.
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

/// Translucent card anchored to the top-right corner, opened from the
/// lyrics ('T') button. Regular users see the lyrics (or the "not added
/// yet" message); developer accounts additionally get an inline
/// add/edit form, since only they are allowed to write lyrics — they're
/// stored as a text object in Yandex Storage, not a database.
class _LyricsPanel extends StatefulWidget {
  const _LyricsPanel({required this.track});
  final Track track;

  @override
  State<_LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<_LyricsPanel> {
  String? _lyrics;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  String? _error;
  late final TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // widget.track can be stale: it usually comes from
      // PlayerProvider.currentTrack, which is the AudioPlayerService's own
      // queue object and isn't touched when LibraryProvider.setLyrics()
      // updates its track list. Re-resolving by id here means a track
      // that just had lyrics added (in this session or another) is
      // picked up immediately, even on a freshly reopened panel.
      final library = context.read<LibraryProvider>();
      final freshTrack = library.trackById(widget.track.id) ?? widget.track;
      final text = await library.fetchLyrics(freshTrack);
      if (!mounted) return;
      setState(() {
        _lyrics = text;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final text = _editController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<LibraryProvider>().setLyrics(trackId: widget.track.id, lyrics: text);
      if (!mounted) return;
      setState(() {
        _lyrics = text;
        _editing = false;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDeveloper = context.watch<AuthProvider>().isDeveloper;
    final size = MediaQuery.of(context).size;
    final panelWidth = (size.width - 32).clamp(0.0, 340.0);

    return Align(
      alignment: Alignment.topRight,
      child: SafeArea(
        child: GestureDetector(
          // Swallow taps inside the card so they don't fall through to
          // the barrier and dismiss the panel.
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.only(top: 64, right: 16, left: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  width: panelWidth,
                  constraints: BoxConstraints(maxHeight: size.height * 0.6),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  // showGeneralDialog (unlike showDialog) does NOT wrap its
                  // pageBuilder content in a Material widget, so anything in
                  // here that needs one — TextField, InkWell, etc. — has to
                  // get its own. MaterialType.transparency keeps it
                  // invisible so it doesn't fight with our custom
                  // frosted-glass background above.
                  child: Material(
                    type: MaterialType.transparency,
                    child: _buildContent(context, isDeveloper),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool isDeveloper) {
    if (_loading) {
      return const SizedBox(
        height: 72,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
          ),
        ),
      );
    }

    if (_editing) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('lyrics'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _editController,
            maxLines: 8,
            minLines: 4,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: context.tr('enter_lyrics_hint'),
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.45)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => setState(() => _editing = false),
                child: Text(context.tr('cancel')),
              ),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(context.tr('save')),
              ),
            ],
          ),
        ],
      );
    }

    final lyrics = _lyrics;
    if (lyrics == null || lyrics.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('lyrics'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr('no_lyrics'),
            style: TextStyle(color: Colors.white.withOpacity(0.75), height: 1.4),
          ),
          if (isDeveloper) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  _editController.text = '';
                  setState(() => _editing = true);
                },
                child: Text(context.tr('add_lyrics')),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('lyrics'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            if (isDeveloper)
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.white70),
                tooltip: context.tr('edit_lyrics'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () {
                  _editController.text = lyrics;
                  setState(() => _editing = true);
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            child: Text(lyrics, style: const TextStyle(color: Colors.white, height: 1.5)),
          ),
        ),
      ],
    );
  }
}
