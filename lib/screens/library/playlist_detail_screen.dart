import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/track_list_tile.dart';

class PlaylistDetailScreen extends StatelessWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final player = context.watch<PlayerProvider>();
    final playlist = library.playlists.firstWhere((p) => p.id == playlistId);
    final tracks = playlist.trackIds.map(library.trackById).whereType<Track>().toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await library.deletePlaylist(playlistId);
              if (context.mounted) Navigator.pop(context);
            },
            tooltip: context.tr('delete_playlist'),
          ),
        ],
      ),
      body: tracks.isEmpty
          ? Center(child: Text(context.tr('empty_playlist'), style: TextStyle(color: Theme.of(context).hintColor)))
          : ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, i) {
                final track = tracks[i];
                return TrackListTile(
                  track: track,
                  isPlaying: player.currentTrack?.id == track.id,
                  onTap: () => player.playQueue(tracks, startIndex: i),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => library.removeFromPlaylist(playlistId, track.id),
                  ),
                );
              },
            ),
    );
  }
}
