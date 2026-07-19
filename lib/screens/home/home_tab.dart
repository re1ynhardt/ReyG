import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../utils/duration_format.dart';
import '../../widgets/section_header.dart';
import '../../widgets/cached_cover_image.dart';
import '../../widgets/track_list_tile.dart';
import '../library/playlist_picker_sheet.dart';
import '../library/tag_tracks_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<LibraryProvider>().loadAll());
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final player = context.watch<PlayerProvider>();
    final featuredTags = library.featuredTags.where((t) => t.isNotEmpty).toList();

    if (library.loading && library.tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: library.loadAll,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(title: Text(context.tr('home')), floating: true),
          if (featuredTags.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionHeader(title: context.tr('featured_tags'))),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 164,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: featuredTags.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, i) {
                    final tag = featuredTags[i];
                    return _TagCoverCard(
                      tag: tag,
                      track: library.latestTrackForTag(tag),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => TagTracksScreen(tag: tag)),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          if (library.recentlyPlayedTracks.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                title: context.tr('recently_played'),
                topSpacing: featuredTags.isNotEmpty ? 12 : 20,
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 210,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: library.recentlyPlayedTracks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, i) {
                    final track = library.recentlyPlayedTracks[i];
                    return _CoverCard(
                      track: track,
                      onTap: () => player.playQueue(library.recentlyPlayedTracks, startIndex: i),
                    );
                  },
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(child: SectionHeader(title: context.tr('all_tracks'))),
          SliverList.builder(
            itemCount: library.tracks.length,
            itemBuilder: (context, i) {
              final track = library.tracks[i];
              final isCurrent = player.currentTrack?.id == track.id;
              return TrackListTile(
                track: track,
                isPlaying: isCurrent,
                onTap: () => player.playQueue(library.tracks, startIndex: i),
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
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

class _CoverCard extends StatelessWidget {
  const _CoverCard({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedCoverImage(
                track: track,
                width: 140,
                height: 140,
                errorBuilder: (context) => Container(
                  width: 140,
                  height: 140,
                  color: Theme.of(context).cardColor,
                  child: const Icon(Icons.music_note),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            Text(formatDuration(track.duration), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }
}

/// Same visual shape as [_CoverCard], but for one of the 4 developer-picked
/// "featured tags" on Home: shows the most recently uploaded track's cover
/// for that hashtag (or a placeholder if no track has it yet) and labels
/// it with the tag itself instead of a title/artist.
class _TagCoverCard extends StatelessWidget {
  const _TagCoverCard({required this.tag, required this.track, required this.onTap});
  final String tag;
  final Track? track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: track == null
                  ? Container(
                      width: 140,
                      height: 140,
                      color: Theme.of(context).cardColor,
                      child: const Icon(Icons.tag),
                    )
                  : CachedCoverImage(
                      track: track!,
                      width: 140,
                      height: 140,
                      errorBuilder: (context) => Container(
                        width: 140,
                        height: 140,
                        color: Theme.of(context).cardColor,
                        child: const Icon(Icons.music_note),
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text('#$tag', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
