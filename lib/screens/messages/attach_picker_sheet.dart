import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/message_attachment.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
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
  late final TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(context.tr('attach'), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: context.tr('attach_track_tab')),
                Tab(text: context.tr('attach_playlist_tab')),
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
                ],
              ),
            ),
          ],
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
