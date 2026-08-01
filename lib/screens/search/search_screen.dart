import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../widgets/artist_result_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/track_list_tile.dart';
import '../library/artist_tracks_screen.dart';
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

  Widget _buildArtistCard(BuildContext context, LibraryProvider library, PlayerProvider player, String? currentTrackId, String artist) {
    final artistTracks = library.tracks.where((t) => t.artist == artist).toList();
    final preview = artistTracks.take(3).toList();
    return ArtistResultCard(
      artist: artist,
      avatarUrl: library.avatarForArtist(artist),
      trackCount: artistTracks.length,
      previewTracks: preview,
      playingTrackId: currentTrackId,
      onListen: () {
        if (artistTracks.isEmpty) return;
        final index = Random().nextInt(artistTracks.length);
        library.commitSearchHistory(_controller.text);
        player.playQueue(artistTracks, startIndex: index);
      },
      onOpen: () {
        library.commitSearchHistory(_controller.text);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistTracksScreen(artist: artist)));
      },
      onTrackTap: (i) {
        library.commitSearchHistory(_controller.text);
        player.playQueue(preview, startIndex: i);
      },
      onTrackMore: (track) => showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        builder: (_) => PlaylistPickerSheet(track: track),
      ),
    );
  }

  Widget _buildResults(BuildContext context, LibraryProvider library, PlayerProvider player, String? currentTrackId) {
    final artists = library.searchArtists(_controller.text);
    final tracks = library.searchResults;

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        if (artists.isNotEmpty) ...[
          SectionHeader(title: context.tr('artists'), topSpacing: 4),
          for (final artist in artists) _buildArtistCard(context, library, player, currentTrackId, artist),
        ],
        if (tracks.isNotEmpty) ...[
          SectionHeader(title: context.tr('tracks'), topSpacing: artists.isEmpty ? 4 : 12),
          for (var i = 0; i < tracks.length; i++)
            TrackListTile(
              track: tracks[i],
              isPlaying: currentTrackId == tracks[i].id,
              onTap: () {
                context.read<LibraryProvider>().commitSearchHistory(_controller.text);
                player.playQueue(tracks, startIndex: i);
              },
              trailing: IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  builder: (_) => PlaylistPickerSheet(track: tracks[i]),
                ),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final currentTrackId = context.select<PlayerProvider, String?>((p) => p.currentTrack?.id);
    final player = context.read<PlayerProvider>();

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
                : (library.searchResults.isEmpty && library.searchArtists(_controller.text).isEmpty)
                    ? Center(
                        child: Text(
                          context.tr('no_results'),
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                      )
                    : _buildResults(context, library, player, currentTrackId),
          ),
        ],
      ),
    );
  }
}
