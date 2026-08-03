import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
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

  // True while a rename request is in flight, so the edit affordance
  // can't be triggered twice at once.
  bool _renameBusy = false;

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

  /// Same frosted-glass dialog style used for the password/bio editors
  /// elsewhere in the app (see settings_screen.dart): a translucent,
  /// blurred surface over the rest of the screen with a soft gradient
  /// card on top, so it reads as premium rather than a stock dialog.
  Future<void> _renamePlaylist(String currentName) async {
    if (_renameBusy) return;
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.32),
      builder: (dialogContext) {
        final dTheme = Theme.of(dialogContext);
        final outline = OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: dTheme.colorScheme.primary.withOpacity(0.12)),
        );
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
                        child: Icon(Icons.edit_outlined, color: dTheme.colorScheme.secondary, size: 22),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        dialogContext.tr('rename_playlist'),
                        textAlign: TextAlign.center,
                        style: dTheme.textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 22),
                      TextFormField(
                        controller: controller,
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        style: dTheme.textTheme.bodyMedium,
                        decoration: InputDecoration(
                          labelText: dialogContext.tr('playlist_name'),
                          isDense: true,
                          filled: true,
                          fillColor: dTheme.colorScheme.primary.withOpacity(0.05),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          border: outline,
                          enabledBorder: outline,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: dTheme.colorScheme.secondary, width: 1.4),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? dialogContext.tr('playlist_name_required') : null,
                        onFieldSubmitted: (_) {
                          if (formKey.currentState!.validate()) {
                            Navigator.of(dialogContext).pop(controller.text.trim());
                          }
                        },
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
                                  Navigator.of(dialogContext).pop(controller.text.trim());
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

    if (newName == null || newName == currentName || !mounted) return;

    setState(() => _renameBusy = true);
    try {
      await context.read<LibraryProvider>().renamePlaylist(playlistId: widget.playlistId, newName: newName);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_trStatic(context, 'playlist_renamed'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _renameBusy = false);
    }
  }

  Widget _buildCoverThumb(BuildContext context, String coverUrl) {
    final ImageProvider? image = coverUrl.isEmpty
        ? null
        : (coverUrl.startsWith('http') ? CachedNetworkImageProvider(coverUrl) : FileImage(File(coverUrl)) as ImageProvider);

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
    final currentTrackId = context.select<PlayerProvider, String?>((p) => p.currentTrack?.id);
    final hasTrack = context.select<PlayerProvider, bool>((p) => p.hasTrack);
    final player = context.read<PlayerProvider>();
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
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _renameBusy ? null : () => _renamePlaylist(playlist.name),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(playlist.name, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                if (_renameBusy)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.edit_outlined, size: 16, color: Theme.of(context).hintColor),
              ],
            ),
          ),
        ),
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
                  onPressed: _renameBusy ? null : () => _renamePlaylist(playlist.name),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(context.tr('rename_playlist')),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                ),
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
                        isPlaying: currentTrackId == track.id,
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
      bottomNavigationBar: hasTrack
          ? Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: const MiniPlayer(),
            )
          : null,
    );
  }
}
