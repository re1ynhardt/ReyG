import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/cached_cover_image.dart';
import '../../widgets/track_list_tile.dart';
import 'playlist_picker_sheet.dart';

/// Every track carrying hashtag [tag], opened by tapping one of the
/// featured-tag covers on Home. Reads live from [LibraryProvider.tracks]
/// (rather than a fixed list) so it stays in sync if a track is added or
/// removed while the screen is open. Tracks are shown newest-upload-first
/// — the same order used everywhere else in the app.
class TagTracksScreen extends StatelessWidget {
  const TagTracksScreen({super.key, required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final player = context.watch<PlayerProvider>();
    final tracks = library.tracksForTag(tag);
    final cover = tracks.isNotEmpty ? tracks.first.coverUrl : '';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 56, bottom: 16, right: 16),
              title: Text(
                '#$tag',
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
    );
  }
}
