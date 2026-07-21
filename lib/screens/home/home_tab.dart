import 'dart:ui';

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

/// Height reserved above the scrollable content on both pages so it
/// clears the floating switcher pill (see [_HomeSwitcherPill]).
double _contentTopInset(BuildContext context) => MediaQuery.of(context).padding.top + 64;

/// Home tab: a "Главная" / "Рекомендации" pair of pages that the person
/// can swipe between (or tap to switch), with a semi-transparent pill
/// widget floating over the top-center of the screen showing which page
/// is active.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<LibraryProvider>().loadAll());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    if (page == _page) return;
    _pageController.animateToPage(page, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();

    if (library.loading && library.tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        PageView(
          controller: _pageController,
          onPageChanged: (i) => setState(() => _page = i),
          children: const [
            _HomeContent(),
            _RecommendationsContent(),
          ],
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 0,
          right: 0,
          child: Center(
            child: _HomeSwitcherPill(index: _page, onChanged: _goToPage),
          ),
        ),
      ],
    );
  }
}

/// The premium, semi-transparent "Главная / Рекомендации" pill. Frosted
/// glass look (blur + low-opacity fill) so it reads as an overlay rather
/// than a normal app bar, with the selected side highlighted using the
/// current theme's accent color.
class _HomeSwitcherPill extends StatelessWidget {
  const _HomeSwitcherPill({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<AppState>().isDark;
    final accent = Theme.of(context).colorScheme.secondary;
    final labels = [context.tr('home'), context.tr('recommendations')];
    final tint = isDark ? Colors.white : Colors.black;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint.withOpacity(isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: tint.withOpacity(0.16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(labels.length, (i) {
                final selected = i == index;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      color: selected ? accent.withOpacity(0.92) : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : tint.withOpacity(0.75),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final player = context.watch<PlayerProvider>();
    final featuredTags = library.featuredTags.where((t) => t.isNotEmpty).toList();

    return RefreshIndicator(
      onRefresh: library.loadAll,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: _contentTopInset(context))),
          if (featuredTags.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionHeader(title: context.tr('featured_tags'), topSpacing: 4)),
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
                topSpacing: featuredTags.isNotEmpty ? 12 : 4,
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

/// Рекомендации: built from the hashtags of the last 5 tracks played on
/// this device — see [LibraryProvider.recommendedTracks] for the
/// selection algorithm. Shown as a plain track list; if there are fewer
/// than 40 tracks (the maximum the algorithm can produce), a hint is
/// appended at the bottom of the list.
class _RecommendationsContent extends StatelessWidget {
  const _RecommendationsContent();

  static const _maxPossible = 5 * Track.maxHashtags * 2;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final player = context.watch<PlayerProvider>();
    final recommended = library.recommendedTracks;

    return RefreshIndicator(
      onRefresh: library.loadAll,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: _contentTopInset(context))),
          if (recommended.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
                child: Text(
                  context.tr('recommendations_hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).hintColor, fontSize: 15, height: 1.4),
                ),
              ),
            )
          else ...[
            SliverList.builder(
              itemCount: recommended.length,
              itemBuilder: (context, i) {
                final track = recommended[i];
                final isCurrent = player.currentTrack?.id == track.id;
                return TrackListTile(
                  track: track,
                  isPlaying: isCurrent,
                  onTap: () => player.playQueue(recommended, startIndex: i),
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
            if (recommended.length < _maxPossible)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
                  child: Text(
                    context.tr('recommendations_hint'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13, height: 1.4),
                  ),
                ),
              ),
          ],
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
