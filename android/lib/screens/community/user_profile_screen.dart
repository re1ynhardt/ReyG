import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../models/user.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/artist_avatar.dart';
import '../../widgets/cached_cover_image.dart';
import '../../widgets/track_list_tile.dart';
import '../library/playlist_picker_sheet.dart';
import '../messages/chat_screen.dart';
import '../player/mini_player.dart';
import '../posts/posts_feed_screen.dart';
import '../settings/banner_crop_screen.dart';

/// Read-only profile for another Community user: their liked (favorited)
/// tracks and their playlists (both already tied to the account in Yandex
/// Storage — `user_id` on favorites rows, `owner_id` on playlists).
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> with SingleTickerProviderStateMixin {
  late Future<List<Track>> _tracksFuture;
  late Future<List<Playlist>> _playlistsFuture;
  /// Whether the signed-in account is allowed to see this user's liked
  /// tracks and playlists at all, per their privacy setting — checked
  /// once up front so the UI can show a "private" message instead of an
  /// empty list when it's hidden rather than just empty.
  late Future<bool> _canViewFuture;
  /// Number of accounts that have favorited this profile's user (their
  /// fan count) — shown as the "Favorites" stat, in place of how many
  /// tracks this account has liked.
  late Future<int> _favoriteUserCountFuture;
  /// Drives the swipe between the two profile pages: "Library" (liked
  /// tracks + playlists, same content this screen always showed) and
  /// "Artist" (tracks this specific account has uploaded).
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final community = context.read<CommunityProvider>();
    _canViewFuture = community.canViewUserLibrary(widget.user.id);
    _tracksFuture = community.fetchUserLikedTracks(widget.user.id);
    _playlistsFuture = community.fetchUserPlaylists(widget.user.id);
    _favoriteUserCountFuture = community.fetchFavoriteUserCount(widget.user.id);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reload() {
    final community = context.read<CommunityProvider>();
    setState(() {
      _canViewFuture = community.canViewUserLibrary(widget.user.id);
      _tracksFuture = community.fetchUserLikedTracks(widget.user.id, forceRefresh: true);
      _playlistsFuture = community.fetchUserPlaylists(widget.user.id, forceRefresh: true);
      _favoriteUserCountFuture = community.fetchFavoriteUserCount(widget.user.id, forceRefresh: true);
    });
  }

  /// Own-profile-only (see the `if (isSelf)` gate on its AppBar action).
  /// Lets the signed-in user pick their PUBLIC profile accent theme — see
  /// [AppUser.profileTheme] and [AuthProvider.setProfileTheme] — right
  /// from their own profile screen rather than from Settings, since
  /// unlike the app-wide theme in Settings this one is what OTHER
  /// viewers of this profile see, not how the app looks to this user.
  Future<void> _pickProfileTheme(String currentKey) async {
    final selected = await showModalBottomSheet<AppThemeOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ProfileThemePickerSheet(
        currentKey: currentKey,
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await context.read<AuthProvider>().setProfileTheme(selected.storageKey);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Opens the developer-only debug sheet. If the account was deleted
  /// from inside it, refreshes the Community list and pops this profile
  /// screen since it no longer refers to a real account.
  Future<void> _openDebugSheet() async {
    final deleted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserDebugSheet(user: widget.user),
    );
    if (deleted == true && mounted) {
      context.read<CommunityProvider>().loadUsers();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTrackId = context.select<PlayerProvider, String?>((p) => p.currentTrack?.id);
    final hasTrack = context.select<PlayerProvider, bool>((p) => p.hasTrack);
    final player = context.read<PlayerProvider>();
    final auth = context.watch<AuthProvider>();
    final community = context.watch<CommunityProvider>();
    final library = context.watch<LibraryProvider>();
    final isDeveloper = auth.hasDeveloperRights;
    final isSelf = auth.user?.id == widget.user.id;
    final isFavorite = community.isFavoriteUser(widget.user.id);
    // widget.user is a snapshot taken when this screen was pushed (e.g.
    // from the Community list), so it goes stale the moment the signed-in
    // user edits their own name/avatar/bio in Settings. For your own
    // profile, prefer the live AuthProvider copy so those edits show up
    // immediately without needing to reopen this screen.
    final user = isSelf ? (auth.user ?? widget.user) : widget.user;
    // Tracks this specific account uploaded (not just tracks credited to
    // them as "artist" — an uploader can type any artist name), shown on
    // the "Artist" page.
    final uploadedTracks = library.tracks.where((t) => t.uploaderId == user.id).toList();
    // Same owner-chosen theme _ProfileHero uses for the accent icon —
    // apply it to the whole screen so the background (scaffold, tab
    // bar, cards, lists) matches too, instead of only the icon.
    final ownerTheme = AppThemeOptionX.fromStorageKey(user.profileTheme).themeData;

    return Theme(
      data: ownerTheme,
      child: Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.dynamic_feed_outlined),
            tooltip: context.tr('user_posts_tooltip'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PostsFeedScreen(authorId: user.id, authorName: user.displayName),
              ),
            ),
          ),
          if (isSelf)
            IconButton(
              icon: const Icon(Icons.palette_outlined),
              tooltip: context.tr('profile_theme'),
              onPressed: () => _pickProfileTheme(user.profileTheme),
            ),
          if (isDeveloper)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: context.tr('debug_user'),
              onPressed: () => _openDebugSheet(),
            ),
        ],
      ),
      body: Column(
        children: [
          FutureBuilder<List<Playlist>>(
            future: _playlistsFuture,
            builder: (context, playlistsSnapshot) {
              return FutureBuilder<int>(
                future: _favoriteUserCountFuture,
                builder: (context, favoriteCountSnapshot) {
                  return _ProfileHero(
                    user: user,
                    uploadedTracksCount: uploadedTracks.length,
                    playlistsCount: playlistsSnapshot.data?.length ?? 0,
                    subscriberCount: favoriteCountSnapshot.data ?? 0,
                    isSelf: isSelf,
                    isSubscribed: isFavorite,
                    onToggleSubscribe: () async {
                      await context.read<CommunityProvider>().toggleFavoriteUser(user.id);
                      if (mounted) {
                        setState(() {
                          _favoriteUserCountFuture =
                              context.read<CommunityProvider>().fetchFavoriteUserCount(user.id, forceRefresh: true);
                        });
                      }
                    },
                  );
                },
              );
            },
          ),
          _ProfileSegmentedTabBar(controller: _tabController),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLibraryTab(context),
                _buildArtistTab(context, uploadedTracks, player, currentTrackId),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: hasTrack
          ? const Padding(padding: EdgeInsets.only(bottom: 6), child: MiniPlayer())
          : null,
      ),
    );
  }

  /// "Library" page: this account's liked tracks and playlists — the
  /// content this screen always showed, unchanged, just now living in its
  /// own swipeable page instead of the whole screen.
  Widget _buildLibraryTab(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          FutureBuilder<bool>(
            future: _canViewFuture,
            builder: (context, canViewSnapshot) {
              if (canViewSnapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (canViewSnapshot.data != true) {
                return _PrivateLibraryCard();
              }
              return Column(
                children: [
                  FutureBuilder<List<Track>>(
                    future: _tracksFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final tracks = snapshot.data ?? const [];
                      return _FavoritesSection(
                        tracks: tracks,
                        onOpen: tracks.isEmpty
                            ? null
                            : () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) =>
                                      _UserTracksScreen(title: context.tr('favorites'), tracks: tracks),
                                )),
                      );
                    },
                  ),
                  FutureBuilder<List<Playlist>>(
                    future: _playlistsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final playlists = snapshot.data ?? const [];
                      return _PlaylistsSection(playlists: playlists);
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// "Artist" page: every track this account has personally uploaded
  /// (matched via [Track.uploaderId], not the free-text artist name), so
  /// it reads live from [LibraryProvider] rather than a one-shot fetch —
  /// it updates immediately if the account uploads/deletes a track while
  /// this profile is open.
  Widget _buildArtistTab(BuildContext context, List<Track> tracks, PlayerProvider player, String? currentTrackId) {
    if (tracks.isEmpty) {
      return Center(
        child: Text(context.tr('user_no_tracks'), style: TextStyle(color: Theme.of(context).hintColor)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: tracks.length,
      itemBuilder: (context, i) => TrackListTile(
        track: tracks[i],
        isPlaying: currentTrackId == tracks[i].id,
        onTap: () => player.playQueue(tracks, startIndex: i),
        trailing: IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => showModalBottomSheet(
            context: context,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            builder: (_) => PlaylistPickerSheet(track: tracks[i]),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the liked-tracks/playlists cards when this profile's
/// privacy setting hides them from the signed-in account (see
/// [CommunityProvider.canViewUserLibrary]).
/// Short profile description shown right under the avatar/name row on a
/// Community profile (see [AppUser.bio], set from Settings). Only
/// rendered when the account has actually set one.
/// Banner + avatar/name header shown when the profile has a banner set.
/// Lays the avatar over the bottom edge of the banner (half on the image,
/// half below it) and bottom-aligns the name with the avatar, using
/// [Stack]/[Positioned] rather than negative margin/padding — both
/// `Container.margin` and `Padding.padding` assert non-negative in
/// Flutter, so an overlap like this can't be done by shifting insets
/// into negative territory.
/// Full-bleed hero header shown at the top of a Community profile: banner
/// (or a themed gradient fallback when the account has no `bannerUrl`) as
/// a backdrop, darkened so the app bar's icons stay legible, with the
/// avatar, display name, badge, bio and Tracks/Playlists/Favorites stats
/// all centered on top of it — mirrors a typical social-profile header
/// instead of the old left-aligned row.
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.user,
    required this.uploadedTracksCount,
    required this.playlistsCount,
    required this.subscriberCount,
    required this.isSelf,
    required this.isSubscribed,
    required this.onToggleSubscribe,
  });

  final AppUser user;
  final int uploadedTracksCount;
  final int playlistsCount;
  final int subscriberCount;
  // Own profile doesn't get Subscribe/Message buttons — you can't
  // subscribe to or message yourself.
  final bool isSelf;
  // Reuses the same favorite-user flag the old app-bar star relied on —
  // "Subscribe" here IS the favorite-user feature, just relocated and
  // restyled as a big button instead of a star icon.
  final bool isSubscribed;
  final VoidCallback onToggleSubscribe;

  static const _avatarRadius = 52.0;

  @override
  Widget build(BuildContext context) {
    // Deliberately NOT Theme.of(context) — this profile's accent comes
    // from the OWNER's chosen [AppUser.profileTheme], set from this same
    // screen (see [_pickProfileTheme]), so every viewer sees the same
    // colors here regardless of their own local app theme.
    final ownerTheme = AppThemeOptionX.fromStorageKey(user.profileTheme).themeData;
    final accent = ownerTheme.colorScheme.secondary;
    final primary = ownerTheme.colorScheme.primary;
    final topPadding = MediaQuery.of(context).padding.top;

    return AspectRatio(
      // Fixed aspect ratio, matching [BannerCropScreen.aspectRatio] exactly,
      // so the frame the user cropped in Settings is exactly what's shown
      // here — no extra `BoxFit.cover` re-cropping or distortion from a
      // mismatched container shape.
      aspectRatio: BannerCropScreen.aspectRatio,
      child: ClipRect(child: _buildStack(context, primary, accent, topPadding)),
    );
  }

  Widget _buildStack(BuildContext context, Color primary, Color accent, double topPadding) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Backdrop: the user's banner photo, or a themed gradient when
        // they haven't set one.
        Positioned.fill(
          child: user.bannerUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: user.bannerUrl,
                  fit: BoxFit.cover,
                  errorWidget: (context, _, __) => _HeroGradientFallback(primary: primary, accent: accent),
                  placeholder: (context, _) => _HeroGradientFallback(primary: primary, accent: accent),
                )
              : _HeroGradientFallback(primary: primary, accent: accent),
        ),
        // Scrim so the app bar icons and centered text stay readable over
        // any photo.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.45),
                  Colors.black.withOpacity(0.35),
                  Colors.black.withOpacity(0.75),
                ],
              ),
            ),
          ),
        ),
        Padding(
          // Trimmed from the original (topPadding + kToolbarHeight + 4) so
          // the avatar/name/bio/stats sit a bit higher, leaving room below
          // for the Subscribe/Message buttons within this same
          // fixed-aspect-ratio banner.
          padding: EdgeInsets.fromLTRB(20, topPadding + kToolbarHeight - 14, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing gradient ring around the avatar.
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [accent, primary],
                  ),
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(0.55), blurRadius: 24, spreadRadius: 1),
                  ],
                ),
                child: ArtistAvatar(imageUrl: user.avatarUrl, radius: _avatarRadius),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (user.isDeveloper || user.isSupport || user.isPerformer) ...[
                    const SizedBox(width: 6),
                    Icon(
                      (user.isDeveloper || user.isSupport) ? Icons.verified : Icons.mic,
                      size: 20,
                      color: accent,
                    ),
                  ],
                ],
              ),
              if (user.isDeveloper || user.isSupport || user.isPerformer)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    user.isDeveloper
                        ? context.tr('developer_account')
                        : user.isSupport
                            ? context.tr('support_account')
                            : context.tr('performer_account'),
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.75)),
                  ),
                ),
              if (user.bio.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    user.bio,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.65)),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _HeroStat(value: uploadedTracksCount, label: context.tr('stat_tracks')),
                  _HeroStatDivider(),
                  _HeroStat(value: playlistsCount, label: context.tr('playlists')),
                  _HeroStatDivider(),
                  _HeroStat(value: subscriberCount, label: context.tr('subscribers')),
                ],
              ),
              if (!isSelf) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _HeroActionButton(
                        label: isSubscribed ? context.tr('profile_subscribed') : context.tr('profile_subscribe'),
                        icon: isSubscribed ? Icons.check : Icons.person_add_alt_1,
                        filled: true,
                        color: accent,
                        onPressed: onToggleSubscribe,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroActionButton(
                        label: context.tr('profile_message'),
                        icon: Icons.mail_outline,
                        filled: false,
                        color: Colors.white,
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            otherUserId: user.id,
                            otherUserDisplayName: user.displayName,
                            otherUserAvatarUrl: user.avatarUrl,
                          ),
                        )),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Big pill-shaped Subscribe/Message button shown over the banner. [filled]
/// gives a solid [color] background (used for Subscribe); otherwise it's a
/// translucent outline (used for Message).
class _HeroActionButton extends StatelessWidget {
  const _HeroActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : Colors.white.withOpacity(0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: filled
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.35)),
                ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: filled ? onColor(color) : Colors.white),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: filled ? onColor(color) : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroGradientFallback extends StatelessWidget {
  const _HeroGradientFallback({required this.primary, required this.accent});

  final Color primary;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.55), primary.withOpacity(0.55), Colors.black],
        ),
      ),
    );
  }
}

/// One "1.2K Tracks"-style stat in the hero header. Compacts large counts
/// (e.g. 1234 -> "1.2K") the way social-profile stat rows usually do.
class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final int value;
  final String label;

  static String _compact(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k < 10 ? 1 : 0)}K';
    }
    final m = n / 1000000;
    return '${m.toStringAsFixed(m < 10 ? 1 : 0)}M';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _compact(value),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12.5, color: Colors.white.withOpacity(0.6))),
      ],
    );
  }
}

class _HeroStatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 22),
      color: Colors.white.withOpacity(0.18),
    );
  }
}

/// Pill-shaped "Library / Artist" switcher, built from scratch instead of
/// a Material [TabBar]: a rounded translucent track with a solid accent
/// pill that slides behind whichever label is selected (following
/// [controller]'s animation 1:1 during swipes, not just on settle). Avoids
/// [TabBar] entirely so there's no default bottom divider line under it.
class _ProfileSegmentedTabBar extends StatelessWidget {
  const _ProfileSegmentedTabBar({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final labels = [context.tr('profile_tab_library'), context.tr('profile_tab_artist')];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.cardColor.withOpacity(0.6),
          borderRadius: BorderRadius.circular(26),
        ),
        child: AnimatedBuilder(
          animation: controller.animation ?? controller,
          builder: (context, _) {
            final t = (controller.animation?.value ?? controller.index.toDouble()).clamp(0.0, 1.0);
            return LayoutBuilder(
              builder: (context, constraints) {
                final segmentWidth = constraints.maxWidth / 2;
                return Stack(
                  children: [
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: t * segmentWidth,
                      width: segmentWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withOpacity(0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(labels.length, (i) {
                        final selected = t.round() == i;
                        return Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => controller.animateTo(i),
                            child: Center(
                              child: Text(
                                labels[i],
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: selected ? onColor(accent) : theme.hintColor,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PrivateLibraryCard extends StatelessWidget {
  const _PrivateLibraryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: theme.hintColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.tr('user_library_private'),
              style: TextStyle(color: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header shared by [_FavoritesSection] and [_PlaylistsSection]:
/// bold title on the left, a small pill count/icon on the right, matching
/// the flat (non-card) section-header style used throughout the redesigned
/// profile.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.count, this.icon, this.onOpen});

  final String title;
  final int? count;
  final IconData? icon;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (icon != null && count != null) ...[
            const SizedBox(width: 6),
            Icon(icon, size: 15, color: theme.hintColor),
            const SizedBox(width: 3),
            Text('$count', style: TextStyle(fontSize: 13, color: theme.hintColor)),
          ],
          const Spacer(),
          if (onOpen != null)
            TextButton(onPressed: onOpen, child: Text(context.tr('go_to'))),
        ],
      ),
    );
  }
}

/// Horizontally scrolling row of the profile's liked tracks, shown as
/// square cover cards with the title/artist underneath — matches a
/// music-app "Favorites" shelf rather than the old vertical list rows.
class _FavoritesSection extends StatelessWidget {
  const _FavoritesSection({required this.tracks, required this.onOpen});

  final List<Track> tracks;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = tracks.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: context.tr('favorites'),
          count: tracks.length,
          icon: Icons.favorite_border,
          onOpen: onOpen,
        ),
        if (preview.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(context.tr('user_no_liked_tracks'), style: TextStyle(color: theme.hintColor)),
          )
        else
          SizedBox(
            height: 136,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: preview.length,
              itemBuilder: (context, i) => _TrackCoverCard(
                track: preview[i],
                onTap: () => context.read<PlayerProvider>().playQueue(tracks, startIndex: i),
              ),
            ),
          ),
      ],
    );
  }
}

class _TrackCoverCard extends StatelessWidget {
  const _TrackCoverCard({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  static const _size = 84.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlaying = context.select<PlayerProvider, bool>((p) => p.currentTrack?.id == track.id);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: SizedBox(
          width: _size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedCoverImage(
                  track: track,
                  width: _size,
                  height: _size,
                  errorBuilder: (context) => Container(
                    width: _size,
                    height: _size,
                    color: theme.cardColor,
                    child: const Icon(Icons.music_note, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isPlaying ? theme.colorScheme.secondary : null,
                ),
              ),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: theme.hintColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrolling row of the profile's playlists, styled to match
/// [_FavoritesSection] — same square-card shelf, just with playlist
/// covers/names/track counts instead of tracks.
class _PlaylistsSection extends StatelessWidget {
  const _PlaylistsSection({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: context.tr('playlists')),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(context.tr('user_no_playlists'), style: TextStyle(color: theme.hintColor)),
          )
        else
          SizedBox(
            height: 136,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: playlists.length,
              itemBuilder: (context, i) => _PlaylistCoverCard(playlist: playlists[i]),
            ),
          ),
      ],
    );
  }
}

class _PlaylistCoverCard extends StatelessWidget {
  const _PlaylistCoverCard({required this.playlist});

  final Playlist playlist;

  static const _size = 84.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = context.watch<LibraryProvider>();
    var displayCover = playlist.coverUrl;
    if (displayCover.isEmpty && playlist.trackIds.isNotEmpty) {
      final lastTrackId = playlist.trackIds.last;
      final match = library.tracks.where((t) => t.id == lastTrackId);
      if (match.isNotEmpty) displayCover = match.first.coverUrl;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _ReadOnlyPlaylistScreen(playlist: playlist)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: SizedBox(
          width: _size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: displayCover.isEmpty
                    ? Container(
                        width: _size,
                        height: _size,
                        color: theme.cardColor,
                        alignment: Alignment.center,
                        child: Icon(Icons.queue_music, size: 22, color: theme.hintColor),
                      )
                    : CachedNetworkImage(
                        imageUrl: displayCover,
                        width: _size,
                        height: _size,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(height: 5),
              Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text(
                '${playlist.trackIds.length}',
                style: TextStyle(fontSize: 11, color: theme.hintColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Developer-only "Отладка пользователя" sheet: shows the account's email,
/// ID and role in a frosted-glass panel (matching [_FavoritesGlassCard] /
/// [_PlaylistsGlassCard]), plus a "Change password" action and a
/// destructive "Delete account" action.
///
/// The actual password is never shown — the backend only ever stores a
/// salted hash (see `YandexStorageApiService._hashPassword`), which is
/// exactly the point of hashing: even developer tooling can't recover the
/// original password, so there's nothing recoverable to display here.
/// "Change password" sets a brand-new one instead, the same way a
/// forgot-password reset would, without ever needing the old value.
/// Bottom sheet listing every [AppThemeOption] as a candidate PUBLIC
/// profile accent theme (see [_UserProfileScreenState._pickProfileTheme]).
/// Pops with the chosen [AppThemeOption], or nothing if dismissed.
class _ProfileThemePickerSheet extends StatelessWidget {
  const _ProfileThemePickerSheet({required this.currentKey});

  final String currentKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = AppThemeOptionX.fromStorageKey(currentKey);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
              decoration: BoxDecoration(
                color: theme.cardColor.withOpacity(0.6),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.palette_outlined, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.tr('profile_theme'),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 30, right: 8, bottom: 4),
                    child: Text(
                      context.tr('profile_theme_subtitle'),
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final option in AppThemeOption.values)
                          RadioListTile<AppThemeOption>(
                            title: Text(context.tr(option.labelKey)),
                            secondary: CircleAvatar(
                              radius: 16,
                              backgroundColor: option.swatch,
                              child: Icon(option.icon, size: 16, color: option.isDark ? Colors.white : Colors.black87),
                            ),
                            value: option,
                            groupValue: current,
                            onChanged: (v) => Navigator.of(context).pop(v),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserDebugSheet extends StatefulWidget {
  const _UserDebugSheet({required this.user});

  final AppUser user;

  @override
  State<_UserDebugSheet> createState() => _UserDebugSheetState();
}

class _UserDebugSheetState extends State<_UserDebugSheet> {
  bool _deleting = false;
  bool _changingPassword = false;

  InputDecoration _passwordFieldDecoration(
    ThemeData theme, {
    required String label,
    required bool obscured,
    required VoidCallback onToggle,
  }) {
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: theme.colorScheme.primary.withOpacity(0.12)),
    );
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: theme.colorScheme.primary.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: outline,
      enabledBorder: outline,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.colorScheme.secondary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      suffixIcon: IconButton(
        splashRadius: 18,
        icon: Icon(
          obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 20,
          color: theme.colorScheme.primary.withOpacity(0.45),
        ),
        onPressed: onToggle,
      ),
    );
  }

  /// Developer-only: sets [widget.user]'s password directly, no old
  /// password required. Same frosted-glass dialog style as the
  /// self-service "change password" flow in Settings.
  Future<void> _changePassword() async {
    if (_changingPassword) return;
    final formKey = GlobalKey<FormState>();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscureNew = true;
    bool obscureConfirm = true;

    final newPassword = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.32),
      builder: (dialogContext) {
        final dTheme = Theme.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 36),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          dTheme.colorScheme.surface.withOpacity(0.72),
                          dTheme.colorScheme.surface.withOpacity(0.5),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                    ),
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dTheme.colorScheme.secondary.withOpacity(0.14),
                            ),
                            child: Icon(Icons.lock_outline, color: dTheme.colorScheme.secondary, size: 22),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            dialogContext.tr('change_password'),
                            textAlign: TextAlign.center,
                            style: dTheme.textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.user.displayName,
                            textAlign: TextAlign.center,
                            style: dTheme.textTheme.bodySmall?.copyWith(color: dTheme.hintColor),
                          ),
                          const SizedBox(height: 22),
                          TextFormField(
                            controller: newController,
                            obscureText: obscureNew,
                            autofocus: true,
                            style: dTheme.textTheme.bodyMedium,
                            decoration: _passwordFieldDecoration(
                              dTheme,
                              label: dialogContext.tr('new_password'),
                              obscured: obscureNew,
                              onToggle: () => setDialogState(() => obscureNew = !obscureNew),
                            ),
                            validator: (v) =>
                                (v == null || v.isEmpty) ? dialogContext.tr('password_required') : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: confirmController,
                            obscureText: obscureConfirm,
                            style: dTheme.textTheme.bodyMedium,
                            decoration: _passwordFieldDecoration(
                              dTheme,
                              label: dialogContext.tr('confirm_password'),
                              obscured: obscureConfirm,
                              onToggle: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                            ),
                            validator: (v) => v != newController.text ? dialogContext.tr('password_mismatch') : null,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: dTheme.colorScheme.primary.withOpacity(0.7),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  onPressed: () => Navigator.of(dialogContext).pop(),
                                  child: Text(dialogContext.tr('cancel')),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: dTheme.colorScheme.secondary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  onPressed: () {
                                    if (formKey.currentState!.validate()) {
                                      Navigator.of(dialogContext).pop(newController.text);
                                    }
                                  },
                                  child: Text(dialogContext.tr('save')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (newPassword == null || !mounted) return;

    setState(() => _changingPassword = true);
    try {
      await context.read<CommunityProvider>().setUserPassword(userId: widget.user.id, newPassword: newPassword);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.trOnce('user_password_updated'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _changingPassword = false);
    }
  }

  Future<void> _confirmDelete() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('delete_account_confirm_title')),
        content: Text(context.tr('delete_account_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('delete'), style: TextStyle(color: theme.colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await context.read<CommunityProvider>().deleteUserAccount(widget.user.id);
      if (!mounted) return;
      // Capture the messenger and translated text before popping — once
      // this sheet is popped, its context is on its way out of the tree,
      // so anything context-dependent needs to happen before that, not
      // after.
      final messenger = ScaffoldMessenger.of(context);
      final deletedMessage = context.trOnce('account_deleted');
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(content: Text(deletedMessage)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.user;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: BoxDecoration(
                color: theme.cardColor.withOpacity(0.6),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xFFFF9F2D), Color(0xFF7B2FF7)]),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.bug_report, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.tr('user_debug_title'),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DebugInfoRow(label: context.tr('email'), value: user.email),
                  _DebugInfoRow(label: context.tr('account_id'), value: user.id),
                  _DebugInfoRow(
                    label: context.tr('account_role'),
                    value: user.isDeveloper
                        ? context.tr('account_role_developer')
                        : user.isSupport
                            ? context.tr('account_role_support')
                            : user.isPerformer
                                ? context.tr('account_role_performer')
                                : context.tr('account_role_user'),
                  ),
                  const SizedBox(height: 4),
                  _DebugInfoRow(label: context.tr('password'), value: '••••••••'),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.tr('account_password_note'),
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.secondary),
                      onPressed: _changingPassword ? null : _changePassword,
                      icon: _changingPassword
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.lock_reset),
                      label: Text(context.tr('change_password')),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                      onPressed: _deleting ? null : _confirmDelete,
                      icon: _deleting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.delete_forever),
                      label: Text(context.tr('delete_account')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DebugInfoRow extends StatelessWidget {
  const _DebugInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _UserTracksScreen extends StatelessWidget {
  const _UserTracksScreen({required this.title, required this.tracks});

  final String title;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final currentTrackId = context.select<PlayerProvider, String?>((p) => p.currentTrack?.id);
    final hasTrack = context.select<PlayerProvider, bool>((p) => p.hasTrack);
    final player = context.read<PlayerProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: tracks.length,
        itemBuilder: (context, i) => TrackListTile(
          track: tracks[i],
          isPlaying: currentTrackId == tracks[i].id,
          onTap: () => player.playQueue(tracks, startIndex: i),
          trailing: IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => showModalBottomSheet(
              context: context,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              builder: (_) => PlaylistPickerSheet(track: tracks[i]),
            ),
          ),
        ),
      ),
      bottomNavigationBar: hasTrack
          ? const Padding(padding: EdgeInsets.only(bottom: 6), child: MiniPlayer())
          : null,
    );
  }
}

/// A different account's playlist, shown read-only — playable, but with no
/// add/remove/cover controls (those stay restricted to the owner via
/// [PlaylistDetailScreen], which only ever operates on the caller's own
/// playlists).
class _ReadOnlyPlaylistScreen extends StatelessWidget {
  const _ReadOnlyPlaylistScreen({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final currentTrackId = context.select<PlayerProvider, String?>((p) => p.currentTrack?.id);
    final hasTrack = context.select<PlayerProvider, bool>((p) => p.hasTrack);
    final player = context.read<PlayerProvider>();
    final trackMap = {for (final t in library.tracks) t.id: t};
    final tracks = playlist.trackIds.map((id) => trackMap[id]).whereType<Track>().toList();

    return Scaffold(
      appBar: AppBar(title: Text(playlist.name)),
      body: tracks.isEmpty
          ? Center(
              child: Text(
                context.tr('empty_playlist'),
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: tracks.length,
              itemBuilder: (context, i) => TrackListTile(
                track: tracks[i],
                isPlaying: currentTrackId == tracks[i].id,
                onTap: () => player.playQueue(tracks, startIndex: i),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    builder: (_) => PlaylistPickerSheet(track: tracks[i]),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: player.hasTrack
          ? const Padding(padding: EdgeInsets.only(bottom: 6), child: MiniPlayer())
          : null,
    );
  }
}
