import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/message_attachment.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/messages_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/track_list_tile.dart';

/// Bottom sheet opened from the chat composer's attach button. Lets the
/// person pick a track (from their favorites, or found via search — even
/// one that isn't favorited) or one of their own playlists, and returns
/// the resulting [MessageAttachment] to the caller (which sends it as a
/// message). Doesn't send anything itself, so the caller stays in
/// control of error handling around the actual `sendMessage` call.
class AttachPickerSheet extends StatefulWidget {
  const AttachPickerSheet({super.key});

  @override
  State<AttachPickerSheet> createState() => _AttachPickerSheetState();
}

class _AttachPickerSheetState extends State<AttachPickerSheet> with SingleTickerProviderStateMixin {
  // Kept in sync with YandexStorageApiService's own rejection rules
  // (_rejectedCoverExtensions / _maxCoverBytes) so a bad pick is caught
  // here before spending a network round trip on it.
  static const _allowedImageExtensions = [
    'jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic', 'heif', 'tif', 'tiff',
  ];
  static const _maxImageBytes = 5 * 1024 * 1024;

  late final TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';
  bool _uploadingImage = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Track> _matchingTracks(LibraryProvider library) {
    final term = _query.trim().toLowerCase();
    if (term.isEmpty) return library.favoriteTracks;
    return library.tracks
        .where((t) => t.title.toLowerCase().contains(term) || t.artist.toLowerCase().contains(term))
        .toList();
  }

  void _sendTrack(Track track) {
    Navigator.pop(
      context,
      MessageAttachment.track(
        id: track.id,
        title: track.title,
        artist: track.artist,
        coverUrl: track.coverUrl,
        audioUrl: track.audioUrl,
        durationSeconds: track.duration.inSeconds,
      ),
    );
  }

  void _sendPlaylist(Playlist playlist) {
    Navigator.pop(
      context,
      MessageAttachment.playlist(
        id: playlist.id,
        playlistName: playlist.name,
        coverUrl: playlist.coverUrl,
        trackIds: playlist.trackIds,
      ),
    );
  }

  Future<void> _pickAndUploadImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedImageExtensions,
    );
    final picked = result?.files.single;
    if (picked?.path == null) return;

    if (picked!.size > _maxImageBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('cover_too_large'))));
      }
      return;
    }

    setState(() => _uploadingImage = true);
    try {
      final attachment = await context.read<MessagesProvider>().uploadImageAttachment(picked.path!);
      if (mounted) Navigator.pop(context, attachment);
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final theme = Theme.of(context);
    final showingSearch = _query.trim().isNotEmpty;
    final tracks = _matchingTracks(library);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(context.tr('attach'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            _AttachSegmentedToggle(
              controller: _tabController,
              labels: [
                context.tr('attach_track_tab'),
                context.tr('attach_playlist_tab'),
                context.tr('attach_image_tab'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            hintText: context.tr('search_hint'),
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: theme.cardColor,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      if (!showingSearch)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(context.tr('favorites'), style: TextStyle(color: theme.hintColor)),
                          ),
                        ),
                      Expanded(
                        child: tracks.isEmpty
                            ? Center(
                                child: Text(
                                  context.tr(showingSearch ? 'no_results' : 'no_favorite_tracks'),
                                  style: TextStyle(color: theme.hintColor),
                                ),
                              )
                            : ListView.builder(
                                itemCount: tracks.length,
                                itemBuilder: (context, index) {
                                  final track = tracks[index];
                                  return TrackListTile(track: track, onTap: () => _sendTrack(track));
                                },
                              ),
                      ),
                    ],
                  ),
                  library.playlists.isEmpty
                      ? Center(
                          child: Text(context.tr('no_playlists_to_attach'), style: TextStyle(color: theme.hintColor)),
                        )
                      : ListView.builder(
                          itemCount: library.playlists.length,
                          itemBuilder: (context, index) {
                            final playlist = library.playlists[index];
                            return _PlaylistRow(playlist: playlist, onTap: () => _sendPlaylist(playlist));
                          },
                        ),
                  Center(
                    child: _uploadingImage
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined, size: 48, color: theme.hintColor),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: _pickAndUploadImage,
                                  child: Text(context.tr('choose_image_file')),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pill-shaped "Track / Playlist / Photo" switcher, built from scratch
/// instead of a Material [TabBar]: a rounded translucent track with a
/// solid accent pill that slides behind whichever label is selected,
/// following [controller]'s animation 1:1 during swipes (not just on
/// settle) — so it still tracks a swipe on the [TabBarView] below, just
/// without [TabBar]'s default underline indicator. Same pattern as
/// user_profile_screen.dart's `_ProfileSegmentedTabBar`, generalized to
/// any number of segments.
class _AttachSegmentedToggle extends StatelessWidget {
  const _AttachSegmentedToggle({required this.controller, required this.labels});

  final TabController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.cardColor.withOpacity(0.6),
          borderRadius: BorderRadius.circular(24),
        ),
        child: AnimatedBuilder(
          animation: controller.animation ?? controller,
          builder: (context, _) {
            final maxIndex = (labels.length - 1).toDouble();
            final t = (controller.animation?.value ?? controller.index.toDouble()).clamp(0.0, maxIndex);
            return LayoutBuilder(
              builder: (context, constraints) {
                final segmentWidth = constraints.maxWidth / labels.length;
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
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
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
                                  fontSize: 13,
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

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist, required this.onTap});
  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: playlist.coverUrl.isEmpty
            ? Container(
                width: 52,
                height: 52,
                color: Theme.of(context).cardColor,
                child: const Icon(Icons.queue_music),
              )
            : Image.network(
                playlist.coverUrl,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 52,
                  height: 52,
                  color: Theme.of(context).cardColor,
                  child: const Icon(Icons.queue_music),
                ),
              ),
      ),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${playlist.trackIds.length} ${context.tr('stat_tracks').toLowerCase()}'),
    );
  }
}
