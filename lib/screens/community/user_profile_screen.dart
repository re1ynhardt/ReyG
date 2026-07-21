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
import '../../widgets/artist_avatar.dart';
import '../../widgets/cached_cover_image.dart';
import '../../widgets/track_list_tile.dart';
import '../library/playlist_picker_sheet.dart';
import '../player/mini_player.dart';

/// Read-only profile for another Community user: their liked (favorited)
/// tracks and their playlists (both already tied to the account in Yandex
/// Storage — `user_id` on favorites rows, `owner_id` on playlists).
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late Future<List<Track>> _tracksFuture;
  late Future<List<Playlist>> _playlistsFuture;

  @override
  void initState() {
    super.initState();
    final community = context.read<CommunityProvider>();
    _tracksFuture = community.fetchUserLikedTracks(widget.user.id);
    _playlistsFuture = community.fetchUserPlaylists(widget.user.id);
  }

  void _reload() {
    final community = context.read<CommunityProvider>();
    setState(() {
      _tracksFuture = community.fetchUserLikedTracks(widget.user.id);
      _playlistsFuture = community.fetchUserPlaylists(widget.user.id);
    });
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
    final player = context.watch<PlayerProvider>();
    final auth = context.watch<AuthProvider>();
    final community = context.watch<CommunityProvider>();
    final isDeveloper = auth.isDeveloper;
    final isSelf = auth.user?.id == widget.user.id;
    final isFavorite = community.isFavoriteUser(widget.user.id);
    final user = widget.user;

    return Scaffold(
      appBar: AppBar(
        title: Text(user.displayName),
        actions: [
          if (!isSelf)
            IconButton(
              icon: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: isFavorite ? Colors.amber : null,
              ),
              tooltip: isFavorite
                  ? context.tr('remove_user_from_favorites')
                  : context.tr('add_user_to_favorites'),
              onPressed: () => context.read<CommunityProvider>().toggleFavoriteUser(user.id),
            ),
          if (isDeveloper)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: context.tr('debug_user'),
              onPressed: () => _openDebugSheet(),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  ArtistAvatar(imageUrl: user.avatarUrl, radius: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        if (user.isDeveloper) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified, size: 14, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(context.tr('developer_account'), style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
                return _FavoritesGlassCard(
                  tracks: tracks,
                  onOpen: tracks.isEmpty
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => _UserTracksScreen(title: context.tr('favorites'), tracks: tracks),
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
                return _PlaylistsGlassCard(playlists: playlists);
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: player.hasTrack
          ? const Padding(padding: EdgeInsets.only(bottom: 6), child: MiniPlayer())
          : null,
    );
  }
}

/// Frosted-glass preview card for the profile's liked tracks: up to 5 most
/// recently liked, labeled "Избранное" (favorites), with a "Перейти"
/// button that opens the full liked-tracks list ([_UserTracksScreen]).
class _FavoritesGlassCard extends StatelessWidget {
  const _FavoritesGlassCard({required this.tracks, required this.onOpen});

  final List<Track> tracks;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = tracks.take(5).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.5),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFA2D48), Color(0xFF7B2FF7)]),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.favorite, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.tr('favorites'),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${tracks.length}',
                            style: TextStyle(fontSize: 13, color: theme.hintColor),
                          ),
                        ],
                      ),
                    ),
                    if (onOpen != null)
                      TextButton(
                        onPressed: onOpen,
                        child: Text(context.tr('go_to')),
                      ),
                  ],
                ),
                if (preview.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                    child: Text(
                      context.tr('user_no_liked_tracks'),
                      style: TextStyle(color: theme.hintColor),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      children: [
                        for (var i = 0; i < preview.length; i++)
                          _FavoriteTrackRow(
                            track: preview[i],
                            onTap: () => context.read<PlayerProvider>().playQueue(tracks, startIndex: i),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteTrackRow extends StatelessWidget {
  const _FavoriteTrackRow({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.watch<PlayerProvider>().currentTrack?.id == track.id;
    final accent = Theme.of(context).colorScheme.secondary;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedCoverImage(
                track: track,
                width: 44,
                height: 44,
                errorBuilder: (context) => Container(
                  width: 44,
                  height: 44,
                  color: Theme.of(context).cardColor,
                  child: const Icon(Icons.music_note, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isPlaying ? accent : null,
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
            if (isPlaying) Icon(Icons.graphic_eq, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

/// Frosted-glass card for the profile's playlists, styled to match
/// [_FavoritesGlassCard] — same blur, translucency and row layout, just with
/// playlist covers/names/track counts instead of tracks.
class _PlaylistsGlassCard extends StatelessWidget {
  const _PlaylistsGlassCard({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.5),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF2FA8F7), Color(0xFF7B2FF7)]),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.queue_music, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr('playlists'),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                    child: Text(
                      context.tr('user_no_playlists'),
                      style: TextStyle(color: theme.hintColor),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      children: [
                        for (final playlist in playlists) _PlaylistGlassRow(playlist: playlist),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistGlassRow extends StatelessWidget {
  const _PlaylistGlassRow({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    var displayCover = playlist.coverUrl;
    if (displayCover.isEmpty && playlist.trackIds.isNotEmpty) {
      final lastTrackId = playlist.trackIds.last;
      final match = library.tracks.where((t) => t.id == lastTrackId);
      if (match.isNotEmpty) displayCover = match.first.coverUrl;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _ReadOnlyPlaylistScreen(playlist: playlist)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: displayCover.isEmpty
                  ? Container(
                      width: 44,
                      height: 44,
                      color: Theme.of(context).cardColor,
                      alignment: Alignment.center,
                      child: Icon(Icons.queue_music, size: 18, color: Theme.of(context).hintColor),
                    )
                  : CachedNetworkImage(
                      imageUrl: displayCover,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${playlist.trackIds.length}',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: Theme.of(context).hintColor),
          ],
        ),
      ),
    );
  }
}

/// Developer-only "Отладка пользователя" sheet: shows the account's email,
/// ID and role in a frosted-glass panel (matching [_FavoritesGlassCard] /
/// [_PlaylistsGlassCard]), plus a destructive "Delete account" action.
///
/// The actual password is never shown — the backend only ever stores a
/// salted hash (see `YandexStorageApiService._hashPassword`), which is
/// exactly the point of hashing: even developer tooling can't recover the
/// original password, so there's nothing recoverable to display here.
class _UserDebugSheet extends StatefulWidget {
  const _UserDebugSheet({required this.user});

  final AppUser user;

  @override
  State<_UserDebugSheet> createState() => _UserDebugSheetState();
}

class _UserDebugSheetState extends State<_UserDebugSheet> {
  bool _deleting = false;

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
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 90),
        itemCount: tracks.length,
        itemBuilder: (context, i) => TrackListTile(
          track: tracks[i],
          isPlaying: player.currentTrack?.id == tracks[i].id,
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
    final player = context.watch<PlayerProvider>();
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
                isPlaying: player.currentTrack?.id == tracks[i].id,
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
