import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/track_list_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      context.read<LibraryProvider>().search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final player = context.watch<PlayerProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('search'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: context.tr('search_hint'),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _controller.clear();
                          library.search('');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (library.searching) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: library.searchResults.isEmpty
                ? Center(
                    child: Text(
                      _controller.text.isEmpty ? '' : context.tr('no_results'),
                      style: TextStyle(color: Theme.of(context).hintColor),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: library.searchResults.length,
                    itemBuilder: (context, i) {
                      final track = library.searchResults[i];
                      return TrackListTile(
                        track: track,
                        isPlaying: player.currentTrack?.id == track.id,
                        onTap: () => player.playQueue(library.searchResults, startIndex: i),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
