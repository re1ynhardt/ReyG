import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/artist_avatar.dart';
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
  // Same image-format/size rules as playlist covers and the account
  // avatar (see YandexStorageApiService._rejectedCoverExtensions) — kept
  // in sync so a bad pick is caught here before a network round trip.
  static const _allowedAvatarExtensions = [
    'jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic', 'heif', 'tif', 'tiff',
  ];
  static const _maxAvatarBytes = 5 * 1024 * 1024;

  // Covers both an upload and a removal in flight — either way the
  // avatar shows a spinner and both actions are disabled until it settles.
  bool _avatarBusy = false;

  // Pull-down-to-dismiss, mirroring the swipe-up gesture that opened this
  // screen. The list itself owns vertical drags (it needs to scroll), so
  // rather than a raw GestureDetector we watch ScrollNotifications the
  // same way RefreshIndicator does: only once the list is already at its
  // top (extentBefore == 0) do we start treating further downward drag as
  // a pull rather than a scroll.
  //
  // Deliberately kept simple: while pulling, _pullExtent just mirrors the
  // finger via Transform.translate below, for visual feedback. Once the
  // pull crosses the dismiss threshold we pop immediately and do NOT touch
  // _pullExtent, the scroll position, or physics — the route's own reverse
  // transition (set up by whoever pushed this screen) takes over from
  // wherever the drag left off and carries it the rest of the way off
  // screen. Earlier versions tried to zero _pullExtent and force the
  // scroll position back to 0 right before popping, on the theory that
  // otherwise the two animations would stack. In practice that reset was
  // the actual bug: it happens instantly, so it painted as the whole
  // screen visibly snapping back to fully open for a beat before the
  // close animation started. Not resetting anything avoids that outright
  // — after the drag ends, nothing is left to generate further
  // ScrollUpdateNotifications, so _pullExtent simply stays put on its own.
  late final AnimationController _snapBackController;
  double _pullExtent = 0;
  bool _tracking = false;
  bool _dismissed = false;

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
    if (_dismissed) return false;

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
          _dismissed = true;
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

  /// Same lookup as `context.tr()`, but reads the locale without
  /// subscribing to changes — safe to call from inside async event
  /// handlers (after an `await`), where `context.tr()`'s `listen: true`
  /// would trip Provider's "used outside build" assertion.
  String _trStatic(BuildContext context, String key) {
    final locale = context.read<AppState>().locale;
    return AppStrings.t(locale, key);
  }

  Future<void> _pickAndUploadAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedAvatarExtensions,
    );
    final picked = result?.files.single;
    if (picked?.path == null) return;

    if (picked!.size > _maxAvatarBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_trStatic(context, 'artist_avatar_too_large'))));
      }
      return;
    }

    setState(() => _avatarBusy = true);
    try {
      await context
          .read<LibraryProvider>()
          .uploadArtistAvatar(artist: widget.artist, localImagePath: picked.path!);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_trStatic(context, 'artist_avatar_updated'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _avatarBusy = true);
    try {
      await context.read<LibraryProvider>().removeArtistAvatar(widget.artist);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_trStatic(context, 'artist_avatar_removed'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Widget _buildAvatar(BuildContext context, String avatarUrl, {required bool isDeveloper}) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        children: [
          ArtistAvatar(imageUrl: avatarUrl, radius: 28),
          if (_avatarBusy)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else if (isDeveloper)
            Positioned(
              right: -2,
              bottom: -2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.edit, size: 12, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final currentTrackId = context.select<PlayerProvider, String?>((p) => p.currentTrack?.id);
    final player = context.read<PlayerProvider>();
    final auth = context.watch<AuthProvider>();
    final tracks = library.tracks.where((t) => t.artist == widget.artist).toList();
    final cover = tracks.isNotEmpty ? tracks.first.coverUrl : '';
    final avatarUrl = library.avatarForArtist(widget.artist);
    final hasCustomAvatar = library.hasCustomArtistAvatar(widget.artist);
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar and artist name share one row, name to
                        // the right of the avatar — matches how the
                        // artist block on Search is laid out.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: (auth.hasDeveloperRights && !_avatarBusy) ? _pickAndUploadAvatar : null,
                              child: _buildAvatar(context, avatarUrl, isDeveloper: auth.hasDeveloperRights),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                widget.artist,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${tracks.length} ${context.tr('all_tracks').toLowerCase()}',
                          style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
                        ),
                        if (auth.hasDeveloperRights)
                          Wrap(
                            spacing: 4,
                            children: [
                              TextButton.icon(
                                onPressed: _avatarBusy ? null : _pickAndUploadAvatar,
                                icon: const Icon(Icons.photo_camera_outlined, size: 16),
                                label: Text(context.tr('change_artist_avatar')),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  alignment: Alignment.centerLeft,
                                ),
                              ),
                              if (hasCustomAvatar)
                                TextButton.icon(
                                  onPressed: _avatarBusy ? null : _removeAvatar,
                                  icon: const Icon(Icons.delete_outline, size: 16),
                                  label: Text(context.tr('remove_artist_avatar')),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    alignment: Alignment.centerLeft,
                                    foregroundColor: Theme.of(context).hintColor,
                                  ),
                                ),
                            ],
                          ),
                      ],
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
                          isPlaying: currentTrackId == track.id,
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
