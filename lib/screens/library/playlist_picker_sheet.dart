import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';

class PlaylistPickerSheet extends StatelessWidget {
  const PlaylistPickerSheet({super.key, required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final isFav = library.isFavorite(track.id);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(isFav ? Icons.favorite : Icons.favorite_border),
            title: Text(context.tr('favorites')),
            onTap: () {
              library.toggleFavorite(track.id);
              Navigator.pop(context);
            },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(context.tr('add_to_playlist'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          ...library.playlists.map(
            (p) => ListTile(
              leading: const Icon(Icons.playlist_add),
              title: Text(p.name),
              trailing: p.trackIds.contains(track.id) ? const Icon(Icons.check) : null,
              onTap: () async {
                await library.addToPlaylist(p.id, track.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(context.tr('new_playlist')),
            onTap: () async {
              Navigator.pop(context);
              final name = await _promptName(context);
              if (name != null && name.trim().isNotEmpty) {
                final playlist = await library.createPlaylist(name.trim());
                await library.addToPlaylist(playlist.id, track.id);
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<String?> _promptName(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('new_playlist')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: ctx.tr('playlist_name')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(ctx.tr('create'))),
        ],
      ),
    );
  }
}
