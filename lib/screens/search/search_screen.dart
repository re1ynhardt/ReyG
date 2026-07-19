import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/section_header.dart';
import '../../widgets/track_list_tile.dart';
import '../library/playlist_picker_sheet.dart';

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
    setState(() {}); // refresh so history vs. results toggles immediately
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final library = context.read<LibraryProvider>();
      library.search(query);
      if (query.trim().isNotEmpty) {
        library.commitSearchHistory(query);
      }
    });
  }

  void _runSearch(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    setState(() {});
    _debounce?.cancel();
    context.read<LibraryProvider>()
      ..search(query)
      ..commitSearchHistory(query);
  }

  Widget _buildHistory(BuildContext context, LibraryProvider library) {
    final history = library.searchHistory;
    if (history.isEmpty) {
      return Center(
        child: Text(
          context.tr('no_search_history'),
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        SectionHeader(
          title: context.tr('recent_searches'),
          trailing: TextButton(
            onPressed: () => context.read<LibraryProvider>().clearSearchHistory(),
            child: Text(context.tr('clear_all')),
          ),
        ),
        for (final query in history)
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(query),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => context.read<LibraryProvider>().removeSearchHistoryItem(query),
            ),
            onTap: () => _runSearch(query),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final player = context.watch<PlayerProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('search')),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: context.tr('recent_searches'),
            onPressed: () {
              _controller.clear();
              _debounce?.cancel();
              library.search('');
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (query) {
                if (query.trim().isNotEmpty) {
                  context.read<LibraryProvider>().commitSearchHistory(query);
                }
              },
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
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (library.searching) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _controller.text.isEmpty
                ? _buildHistory(context, library)
                : library.searchResults.isEmpty
                    ? Center(
                        child: Text(
                          context.tr('no_results'),
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
                            onTap: () {
                              context.read<LibraryProvider>().commitSearchHistory(_controller.text);
                              player.playQueue(library.searchResults, startIndex: i);
                            },
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
          ),
        ],
      ),
    );
  }
}
