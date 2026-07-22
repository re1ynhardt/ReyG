import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../services/download_service.dart';
import '../../widgets/track_list_tile.dart';
import '../admin/upload_screen.dart';
import '../player/mini_player.dart';
import 'playlist_detail_screen.dart';
import 'playlist_picker_sheet.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final auth = context.watch<AuthProvider>();
    final downloads = context.watch<DownloadService>();
    // Newest-cached-first, same ordering DownloadService persists them in.
    final trackMap = {for (final t in library.tracks) t.id: t};
    final cachedTracks =
        downloads.cachedTrackIds.map((id) => trackMap[id]).whereType<Track>().toList();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('library'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFA2D48), Color(0xFF7B2FF7)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.favorite, color: Colors.white),
            ),
            title: Text(context.tr('liked_songs'), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${library.favoriteTracks.length}'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _SimpleTrackListScreen(
                title: context.tr('liked_songs'),
                tracks: library.favoriteTracks,
                emptyText: context.tr('empty_favorites'),
              ),
            )),
          ),
          ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.history),
            ),
            title: Text(context.tr('recently_played'), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${library.recentlyPlayedTracks.length}'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _SimpleTrackListScreen(
                title: context.tr('recently_played'),
                tracks: library.recentlyPlayedTracks,
                emptyText: context.tr('empty_recent'),
              ),
            )),
          ),
          ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.download_done),
            ),
            title: Text(context.tr('cached_tracks'), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${cachedTracks.length}'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _SimpleTrackListScreen(
                title: context.tr('cached_tracks'),
                tracks: cachedTracks,
                emptyText: context.tr('empty_cached'),
              ),
            )),
          ),
          if (auth.canManageTracks)
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.cloud_upload, color: Colors.white),
              ),
              title: Text(context.tr('upload_track'), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Row(
                children: [
                  const Icon(Icons.verified, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    auth.isSupport ? context.tr('support_account') : context.tr('performer_account'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadScreen())),
            ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.tr('playlists'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _createPlaylist(context),
                ),
              ],
            ),
          ),
          ...library.playlists.map((p) {
            // Playlists have no cover art of their own until the user sets
            // one explicitly (cover_url stays ''), so fall back to the
            // cover of the most recently added track instead of a plain
            // gray box.
            var displayCover = p.coverUrl;
            if (displayCover.isEmpty && p.trackIds.isNotEmpty) {
              final lastTrackId = p.trackIds.last;
              final match = library.tracks.where((t) => t.id == lastTrackId);
              if (match.isNotEmpty) displayCover = match.first.coverUrl;
            }
            final coverImage = displayCover.isEmpty
                ? null
                : (displayCover.startsWith('http')
                    ? CachedNetworkImageProvider(displayCover)
                    : FileImage(File(displayCover)) as ImageProvider);
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: coverImage == null
                    ? Container(
                        width: 48,
                        height: 48,
                        color: Theme.of(context).cardColor,
                        alignment: Alignment.center,
                        child: Icon(Icons.music_note, size: 20, color: Theme.of(context).hintColor),
                      )
                    : Image(
                        image: coverImage,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
              ),
              title: Text(p.name),
              subtitle: Text('${p.trackIds.length} tracks'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlistId: p.id)),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('new_playlist')),
        content: TextField(controller: controller, autofocus: true,
            decoration: InputDecoration(hintText: ctx.tr('playlist_name'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(ctx.tr('create'))),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty && context.mounted) {
      await context.read<LibraryProvider>().createPlaylist(name.trim());
    }
  }
}

class _SimpleTrackListScreen extends StatelessWidget {
  const _SimpleTrackListScreen({required this.title, required this.tracks, required this.emptyText});
  final String title;
  final List tracks;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: tracks.isEmpty
          ? Center(child: Text(emptyText, style: TextStyle(color: Theme.of(context).hintColor)))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 90),
              itemCount: tracks.length,
              itemBuilder: (context, i) {
                final track = tracks[i];
                return TrackListTile(
                  track: track,
                  isPlaying: player.currentTrack?.id == track.id,
                  onTap: () => player.playQueue(List.from(tracks), startIndex: i),
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
      bottomNavigationBar: player.hasTrack
          ? Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: const MiniPlayer(),
            )
          : null,
    );
  }
}
