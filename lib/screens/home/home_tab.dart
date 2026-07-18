import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/section_header.dart';
import '../../widgets/track_list_tile.dart';
import '../library/playlist_picker_sheet.dart';

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

    if (library.loading && library.tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: library.loadAll,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(title: Text(context.tr('home')), floating: true),
          if (library.recentlyPlayedTracks.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionHeader(title: context.tr('recently_played'))),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 190,
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
              child: Image.network(
                track.coverUrl,
                width: 140,
                height: 140,
                fit: BoxFit.cover,
                cacheWidth: (140 * MediaQuery.of(context).devicePixelRatio).round(),
                errorBuilder: (_, __, ___) => Container(
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
          ],
        ),
      ),
    );
  }
}
