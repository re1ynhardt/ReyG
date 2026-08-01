import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/message_attachment.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/track_list_tile.dart';

/// Opened by tapping a playlist attachment bubble in a chat thread.
/// Playlist attachments only carry track ids (see message_attachment.dart)
/// — this resolves them against the shared, global track catalog
/// (already loaded for every account via [LibraryProvider.tracks]) so it
/// works for the recipient without needing access to the sender's own
/// playlist. Ids that no longer exist in the catalog (e.g. the track was
/// since deleted) are silently skipped.
class AttachmentPlaylistSheet extends StatelessWidget {
  const AttachmentPlaylistSheet({super.key, required this.attachment});
  final MessageAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final trackMap = {for (final t in library.tracks) t.id: t};
    final tracks = attachment.trackIds.map((id) => trackMap[id]).whereType<Track>().toList();
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      attachment.playlistName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (tracks.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => context.read<PlayerProvider>().playQueue(tracks, startIndex: 0),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(context.tr('play')),
                    ),
                ],
              ),
            ),
            if (tracks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.tr('no_results'), style: TextStyle(color: theme.hintColor)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return TrackListTile(
                      track: track,
                      onTap: () => context.read<PlayerProvider>().playQueue(tracks, startIndex: index),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
