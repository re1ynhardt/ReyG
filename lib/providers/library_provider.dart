import 'package:flutter/material.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';

class LibraryProvider extends ChangeNotifier {
  LibraryProvider(this._api);

  final ApiService _api;

  List<Track> _tracks = [];
  List<Playlist> _playlists = [];
  Set<String> _favoriteIds = {};
  List<String> _recentlyPlayedIds = [];

  List<Track> _searchResults = [];
  bool _searching = false;
  bool _loading = false;

  List<Track> get tracks => _tracks;
  List<Playlist> get playlists => _playlists;
  Set<String> get favoriteIds => _favoriteIds;
  List<Track> get searchResults => _searchResults;
  bool get searching => _searching;
  bool get loading => _loading;

  List<Track> get favoriteTracks =>
      _tracks.where((t) => _favoriteIds.contains(t.id)).toList();

  List<Track> get recentlyPlayedTracks {
    final map = {for (final t in _tracks) t.id: t};
    return _recentlyPlayedIds.map((id) => map[id]).whereType<Track>().toList();
  }

  Track? trackById(String id) {
    for (final t in _tracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> loadAll() async {
    _loading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        _api.fetchTracks(),
        _api.fetchPlaylists(),
        _api.fetchFavoriteIds(),
        CacheService.instance.getRecentlyPlayed(),
      ]);
      _tracks = results[0] as List<Track>;
      _playlists = results[1] as List<Playlist>;
      _favoriteIds = (results[2] as List<String>).toSet();
      _recentlyPlayedIds = results[3] as List<String>;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }
    _searching = true;
    notifyListeners();
    try {
      _searchResults = await _api.searchTracks(query);
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  Future<void> markPlayed(String trackId) async {
    await CacheService.instance.addRecentlyPlayed(trackId);
    _recentlyPlayedIds.remove(trackId);
    _recentlyPlayedIds.insert(0, trackId);
    notifyListeners();
  }

  Future<void> toggleFavorite(String trackId) async {
    final isFav = _favoriteIds.contains(trackId);
    if (isFav) {
      _favoriteIds.remove(trackId);
    } else {
      _favoriteIds.add(trackId);
    }
    notifyListeners();
    await _api.setFavorite(trackId: trackId, favorite: !isFav);
  }

  bool isFavorite(String trackId) => _favoriteIds.contains(trackId);

  Future<Playlist> createPlaylist(String name) async {
    final playlist = await _api.createPlaylist(name);
    _playlists = [..._playlists, playlist];
    notifyListeners();
    return playlist;
  }

  Future<void> addToPlaylist(String playlistId, String trackId) async {
    await _api.addTrackToPlaylist(playlistId: playlistId, trackId: trackId);
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1 && !_playlists[idx].trackIds.contains(trackId)) {
      _playlists[idx] = _playlists[idx].copyWith(
        trackIds: [..._playlists[idx].trackIds, trackId],
      );
      notifyListeners();
    }
  }

  Future<void> removeFromPlaylist(String playlistId, String trackId) async {
    await _api.removeTrackFromPlaylist(playlistId: playlistId, trackId: trackId);
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      _playlists[idx] = _playlists[idx].copyWith(
        trackIds: _playlists[idx].trackIds.where((id) => id != trackId).toList(),
      );
      notifyListeners();
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _api.deletePlaylist(playlistId);
    _playlists = _playlists.where((p) => p.id != playlistId).toList();
    notifyListeners();
  }

  Future<Track> uploadTrack({
    required String title,
    required String artist,
    required String album,
    required String localAudioPath,
    String? localCoverPath,
  }) async {
    final track = await _api.uploadTrack(
      title: title,
      artist: artist,
      album: album,
      localAudioPath: localAudioPath,
      localCoverPath: localCoverPath,
    );
    _tracks = [track, ..._tracks];
    notifyListeners();
    return track;
  }

  /// Developer-only. Removes the track everywhere at once: the main
  /// catalog, every playlist that contained it, and every favorites list
  /// (including the current user's) — all three surfaces the person asked
  /// about (Home, Search, Favorites) read from the same [_tracks] /
  /// [_favoriteIds] / [_playlists] state, so one call here updates all of
  /// them immediately without needing a full reload.
  Future<void> deleteTrack(String trackId) async {
    await _api.deleteTrack(trackId);
    _tracks = _tracks.where((t) => t.id != trackId).toList();
    _favoriteIds.remove(trackId);
    _playlists = _playlists
        .map((p) => p.copyWith(trackIds: p.trackIds.where((id) => id != trackId).toList()))
        .toList();
    _searchResults = _searchResults.where((t) => t.id != trackId).toList();
    notifyListeners();
  }
}
