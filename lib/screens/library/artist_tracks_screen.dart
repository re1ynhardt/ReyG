import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/cached_cover_image.dart';
import '../../widgets/track_list_tile.dart';
import 'playlist_picker_sheet.dart';

/// Full list of every track by a single artist, opened by swiping up from
/// the Now Playing screen. Reads live from [LibraryProvider.tracks] (rather
/// than taking a fixed list) so it stays in sync if a developer adds or
/// removes a track for this artist while the screen is open.
class ArtistTracksScreen extends StatefulWidget {
  const ArtistTracksScreen({super.key, required this.artist});

  final String artist;

  @override
  State<ArtistTracksScreen> createState() => _ArtistTracksScreenState();
}

class _ArtistTracksScreenState extends State<ArtistTracksScreen>
    with SingleTickerProviderStateMixin {
  // Pull-down-to-dismiss, mirroring the swipe-up gesture that opened this
  // screen. The list itself owns vertical drags (it needs to scroll), so
  // rather than a raw GestureDetector we watch ScrollNotifications the
  // same way RefreshIndicator does: only once the list is already at its
  // top (extentBefore == 0) do we start treating further downward drag as
  // a pull rather than a scroll.
  late final AnimationController _snapBackController;
  double _pullExtent = 0;
  bool _tracking = false;
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

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_dismissing) return false;

    if (notification is ScrollStartNotification) {
      _tracking = notification.metrics.extentBefore == 0.0;
    } else if (notification is ScrollUpdateNotification) {
      final atTop = notification.metrics.extentBefore == 0.0;
      final dragDelta = notification.dragDetails?.delta.dy;
      if (_tracking && atTop && dragDelta != null) {
        if (_snapBackController.isAnimating) _snapBackController.stop();
        setState(() => _pullExtent = (_pullExtent + dragDelta).clamp(0.0, double.infinity));
      } else if (!atTop && _pullExtent != 0) {
        // The list scrolled away from the top under its own momentum
        // (or the drag stopped being a "pull") — stop tracking and snap
        // whatever pull had accumulated back to zero.
        _tracking = false;
        _snapBack();
      }
    } else if (notification is ScrollEndNotification) {
      if (_tracking && _pullExtent > 0) {
        _tracking = false;
        final screenHeight = MediaQuery.of(context).size.height;
        final velocity = notification.dragDetails?.primaryVelocity ?? 0;
        final shouldDismiss = _pullExtent > screenHeight * 0.18 || velocity > 800;
        if (shouldDismiss) {
          // Reset the manual drag offset to 0 in the same frame we pop.
          // If we left _pullExtent at its dragged-to value, the route's
          // own reverse SlideTransition (which animates from a fully
          // visible Offset.zero) would stack on top of it — the content
          // jumps from "already translated by the drag" to "translated
          // by drag + route offset", which is what produced the visible
          // stutter/hang on close. Zeroing it here hands off cleanly:
          // the drag offset disappears on the same frame the route
          // transition takes over, so there's nothing to see.
          setState(() {
            _dismissing = true;
            _pullExtent = 0;
          });
          Navigator.of(context).pop();
        } else {
          _snapBack();
        }
      }
    }
    return false;
  }

  void _snapBack() {
    final tween = Tween<double>(begin: _pullExtent, end: 0).animate(
      CurvedAnimation(parent: _snapBackController, curve: Curves.easeOutCubic),
    );
    void listener() => setState(() => _pullExtent = tween.value);
    tween.addListener(listener);
    _snapBackController.forward(from: 0).whenCompleteOrCancel(() {
      tween.removeListener(listener);
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final player = context.watch<PlayerProvider>();
    final tracks = library.tracks.where((t) => t.artist == widget.artist).toList();
    final cover = tracks.isNotEmpty ? tracks.first.coverUrl : '';
    final screenHeight = MediaQuery.of(context).size.height;
    final pullProgress = (_pullExtent / screenHeight).clamp(0.0, 1.0);

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: Opacity(
          opacity: 1 - pullProgress * 0.5,
          child: Transform.translate(
            offset: Offset(0, _pullExtent),
            child: CustomScrollView(
              // Force overscroll (bounce) physics on every platform, not
              // just iOS. With the Android default (ClampingScrollPhysics)
              // the scroll position simply stops at 0 when you drag down
              // past the top, so no ScrollUpdateNotification is ever
              // fired and _handleScrollNotification never sees the pull
              // that's supposed to dismiss this screen. Bouncing physics
              // lets the position go negative during the drag, which is
              // what drives the pull-down-to-dismiss gesture below.
              // AlwaysScrollableScrollPhysics as the parent also makes
              // sure the drag is recognized even when there are few
              // enough tracks that the content doesn't fill the viewport.
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 220,
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
                    title: Text(
                      widget.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        cover.isEmpty
                            ? Container(color: Theme.of(context).cardColor)
                            : CachedCoverImage(
                                track: tracks.first,
                                errorBuilder: (_) => Container(color: Theme.of(context).cardColor),
                              ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.15),
                                Theme.of(context).scaffoldBackgroundColor,
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '${tracks.length} ${context.tr('all_tracks').toLowerCase()}',
                      style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
                    ),
                  ),
                ),
                if (tracks.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(context.tr('no_results'), style: TextStyle(color: Theme.of(context).hintColor)),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final track = tracks[i];
                        return TrackListTile(
                          track: track,
                          isPlaying: player.currentTrack?.id == track.id,
                          onTap: () => player.playQueue(tracks, startIndex: i),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => showModalBottomSheet(
                              context: context,
                              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                              builder: (_) => PlaylistPickerSheet(track: track),
                            ),
                          ),
                        );
                      },
                      childCount: tracks.length,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
