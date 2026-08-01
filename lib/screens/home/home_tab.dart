import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../models/user.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../utils/duration_format.dart';
import '../../widgets/section_header.dart';
import '../../widgets/cached_cover_image.dart';
import '../../widgets/track_list_tile.dart';
import '../library/playlist_picker_sheet.dart';
import '../library/tag_tracks_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../../widgets/notifications_shade.dart';

/// Home tab: a fixed header (greeting + notifications/profile, a search
/// bar, and a "Home / Recommendations" switcher) above a pair of pages
/// that the person can swipe between (or tap the switcher to jump to).
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
    setState(() => _page = page);
    if (_pageController.hasClients) {
      _pageController.animateToPage(page, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _HomeHeader(),
                const SizedBox(height: 14),
                const _HomeSearchBar(),
              ],
            ),
          ),
        ),
        Expanded(
          child: library.loading && library.tracks.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Stack(
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
                      top: 12,
                      left: 16,
                      right: 16,
                      child: _HomeSwitcherPill(index: _page, onChanged: _goToPage),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Height reserved at the top of the Home/Recommendations scroll content
/// so it starts below the floating switcher pill instead of underneath it.
const double _switcherClearance = 64;

/// "Home" title, time-of-day greeting, and the notifications/profile
/// buttons in the top-right corner.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  String _greetingKey() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'good_morning';
    if (hour < 18) return 'good_afternoon';
    return 'good_evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.watch<AuthProvider>().user;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('home'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    context.tr(_greetingKey()),
                    style: TextStyle(fontSize: 14, color: theme.hintColor),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.auto_awesome, size: 14, color: theme.hintColor),
                ],
              ),
            ],
          ),
        ),
        _HeaderIconButton(
          icon: Icons.notifications_none_rounded,
          onTap: () => showNotificationsShade(context),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          child: _HeaderAvatar(user: user),
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: theme.cardColor, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: theme.iconTheme.color),
      ),
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({required this.user});
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String avatarUrl = user?.avatarUrl ?? '';
    final String displayName = user?.displayName ?? '';
    final ImageProvider? image = avatarUrl.isEmpty
        ? null
        : (avatarUrl.startsWith('http')
            ? CachedNetworkImageProvider(avatarUrl) as ImageProvider
            : FileImage(File(avatarUrl)));

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: theme.cardColor, shape: BoxShape.circle),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: Colors.transparent,
        backgroundImage: image,
        child: image == null
            ? Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              )
            : null,
      ),
    );
  }
}

/// Tappable search field that opens the full [SearchScreen].
class _HomeSearchBar extends StatelessWidget {
  const _HomeSearchBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: theme.cardColor, borderRadius: BorderRadius.circular(24)),
        child: Row(
          children: [
            Icon(Icons.search, size: 20, color: theme.hintColor),
            const SizedBox(width: 10),
            Text(context.tr('search_hint'), style: TextStyle(color: theme.hintColor, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

/// The "Главная / Рекомендации" segmented switcher — a frosted-glass
/// track with a semi-transparent raised pill over the selected side, in
/// normal document flow (not a floating overlay) directly under the
/// search bar.
class _HomeSwitcherPill extends StatelessWidget {
  const _HomeSwitcherPill({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = [context.tr('home'), context.tr('recommendations')];
    final isDark = theme.brightness == Brightness.dark;
    final tint = isDark ? Colors.white : Colors.black;
    final ink = theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: tint.withOpacity(isDark ? 0.10 : 0.06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: tint.withOpacity(0.12)),
          ),
          child: Row(
            children: List.generate(labels.length, (i) {
              final selected = i == index;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? theme.cardColor.withOpacity(0.55) : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? ink : theme.hintColor,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// "See all" trailing label used on section headers — purely a visual
/// affordance (matches the reference design); the sections it labels
/// don't currently have a dedicated "browse all" destination.
class _SeeAllLabel extends StatelessWidget {
  const _SeeAllLabel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(context.tr('see_all'), style: TextStyle(fontSize: 13, color: theme.hintColor, fontWeight: FontWeight.w500)),
        Icon(Icons.chevron_right, size: 18, color: theme.hintColor),
      ],
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final currentTrackId = context.select<PlayerProvider, String?>((p) => p.currentTrack?.id);
    final player = context.read<PlayerProvider>();
    final featuredTags = library.featuredTags.where((t) => t.isNotEmpty).toList();

    return RefreshIndicator(
      onRefresh: library.loadAll,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: _switcherClearance)),
          if (featuredTags.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(title: context.tr('featured_tags'), topSpacing: 4, trailing: const _SeeAllLabel()),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 130,
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
                trailing: const _SeeAllLabel(),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 168,
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
          SliverToBoxAdapter(
            child: SectionHeader(
              title: context.tr('all_tracks'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 20, color: Theme.of(context).hintColor),
                  const SizedBox(width: 16),
                  Icon(Icons.format_list_bulleted, size: 22, color: Theme.of(context).hintColor),
                ],
              ),
            ),
          ),
          SliverList.builder(
            itemCount: library.tracks.length,
            itemBuilder: (context, i) {
              final track = library.tracks[i];
              final isCurrent = currentTrackId == track.id;
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
    final currentTrackId = context.select<PlayerProvider, String?>((p) => p.currentTrack?.id);
    final player = context.read<PlayerProvider>();
    final recommended = library.recommendedTracks;

    return RefreshIndicator(
      onRefresh: library.loadAll,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: _switcherClearance)),
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
                final isCurrent = currentTrackId == track.id;
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
        width: 108,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: CachedCoverImage(
                track: track,
                width: 108,
                height: 108,
                errorBuilder: (context) => Container(
                  width: 108,
                  height: 108,
                  color: Theme.of(context).cardColor,
                  child: const Icon(Icons.music_note),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
            Text(formatDuration(track.duration), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
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
        width: 100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: track == null
                  ? Container(
                      width: 100,
                      height: 100,
                      color: Theme.of(context).cardColor,
                      child: const Icon(Icons.tag),
                    )
                  : CachedCoverImage(
                      track: track!,
                      width: 100,
                      height: 100,
                      errorBuilder: (context) => Container(
                        width: 100,
                        height: 100,
                        color: Theme.of(context).cardColor,
                        child: const Icon(Icons.music_note),
                      ),
                    ),
            ),
            const SizedBox(height: 5),
            Text('#$tag', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
