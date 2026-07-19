import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/track_list_tile.dart';
import '../player/mini_player.dart';

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  // Any image format is accepted except GIF — kept in sync with the
  // extensions the backend/storage layer rejects server-side (see
  // YandexStorageApiService._rejectedCoverExtensions), so a bad pick is
  // caught here before spending a network round trip on it.
  static const _allowedCoverExtensions = [
    'jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic', 'heif', 'tif', 'tiff',
  ];
  static const _maxCoverBytes = 5 * 1024 * 1024;

  // Covers both an upload and a removal in flight — either way the thumb
  // shows a spinner and both buttons are disabled until it settles.
  bool _coverBusy = false;

  /// Same lookup as `context.tr()`, but reads the locale without
  /// subscribing to changes — safe to call from inside async event
  /// handlers (after an `await`), where `context.tr()`'s `listen: true`
  /// would trip Provider's "used outside build" assertion.
  String _trStatic(BuildContext context, String key) {
    final locale = context.read<AppState>().locale;
    return AppStrings.t(locale, key);
  }

  Future<void> _pickAndUploadCover() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedCoverExtensions,
    );
    final picked = result?.files.single;
    if (picked?.path == null) return;

    if (picked!.size > _maxCoverBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_trStatic(context, 'cover_too_large'))));
      }
      return;
    }

    setState(() => _coverBusy = true);
    try {
      await context
          .read<LibraryProvider>()
          .uploadPlaylistCover(playlistId: widget.playlistId, localImagePath: picked.path!);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_trStatic(context, 'cover_updated'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _coverBusy = false);
    }
  }

  Future<void> _removeCover() async {
    setState(() => _coverBusy = true);
    try {
      await context.read<LibraryProvider>().removePlaylistCover(widget.playlistId);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_trStatic(context, 'cover_removed'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _coverBusy = false);
    }
  }

  Widget _buildCoverThumb(BuildContext context, String coverUrl) {
    final ImageProvider? image = coverUrl.isEmpty
        ? null
        : (coverUrl.startsWith('http') ? NetworkImage(coverUrl) : FileImage(File(coverUrl)) as ImageProvider);

    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 64,
              height: 64,
              color: Theme.of(context).cardColor,
              child: image == null
                  ? Icon(Icons.music_note, color: Theme.of(context).hintColor)
                  : Image(image: image, fit: BoxFit.cover, width: 64, height: 64),
            ),
          ),
          if (_coverBusy)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
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
    final player = context.watch<PlayerProvider>();
    final playlist = library.playlists.firstWhere((p) => p.id == widget.playlistId);
    final tracks = playlist.trackIds.map(library.trackById).whereType<Track>().toList();

    // A playlist with no custom cover of its own (coverUrl == '') falls
    // back to the most recently added track's cover — same rule
    // library_screen.dart uses for the playlist list, so the thumb here
    // matches what's shown there. "Remove cover" only makes sense (and
    // only shows) when there's an actual custom cover to remove.
    final hasCustomCover = playlist.coverUrl.isNotEmpty;
    final displayCover = hasCustomCover ? playlist.coverUrl : (tracks.isNotEmpty ? tracks.last.coverUrl : '');

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await library.deletePlaylist(widget.playlistId);
              if (context.mounted) Navigator.pop(context);
            },
            tooltip: context.tr('delete_playlist'),
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: GestureDetector(
              onTap: _coverBusy ? null : _pickAndUploadCover,
              child: _buildCoverThumb(context, displayCover),
            ),
            title: Text('${tracks.length} ${context.tr('all_tracks').toLowerCase()}'),
            subtitle: Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _coverBusy ? null : _pickAndUploadCover,
                  icon: const Icon(Icons.photo_camera_outlined, size: 16),
                  label: Text(context.tr('change_cover')),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                ),
                if (hasCustomCover)
                  TextButton.icon(
                    onPressed: _coverBusy ? null : _removeCover,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(context.tr('remove_cover')),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                      foregroundColor: Theme.of(context).hintColor,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: tracks.isEmpty
                ? Center(
                    child: Text(context.tr('empty_playlist'), style: TextStyle(color: Theme.of(context).hintColor)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: tracks.length,
                    itemBuilder: (context, i) {
                      final track = tracks[i];
                      return TrackListTile(
                        track: track,
                        isPlaying: player.currentTrack?.id == track.id,
                        onTap: () => player.playQueue(tracks, startIndex: i),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => library.removeFromPlaylist(widget.playlistId, track.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
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
