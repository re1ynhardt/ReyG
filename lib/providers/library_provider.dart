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
  // Ordered newest-favorited-first. The backend appends new favorites to
  // the end of its collection (oldest → newest), so loadAll() reverses
  // it on the way in; toggleFavorite() then keeps it in sync locally by
  // inserting new favorites at index 0 instead of appending.
  List<String> _favoriteIds = [];
  List<String> _recentlyPlayedIds = [];

  List<Track> _searchResults = [];
  bool _searching = false;
  bool _loading = false;
  List<String> _searchHistory = [];

  List<Track> get tracks => _tracks;
  List<Playlist> get playlists => _playlists;
  Set<String> get favoriteIds => _favoriteIds.toSet();
  List<Track> get searchResults => _searchResults;
  bool get searching => _searching;
  bool get loading => _loading;
  List<String> get searchHistory => _searchHistory;

  List<Track> get favoriteTracks {
    final map = {for (final t in _tracks) t.id: t};
    return _favoriteIds.map((id) => map[id]).whereType<Track>().toList();
  }

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
        CacheService.instance.getSearchHistory(),
      ]);
      _tracks = results[0] as List<Track>;
      _playlists = results[1] as List<Playlist>;
      _favoriteIds = (results[2] as List<String>).reversed.toList();
      _recentlyPlayedIds = results[3] as List<String>;
      _searchHistory = results[4] as List<String>;
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

  /// Saves [query] into the on-device search history cache (not the
  /// backend/database) and moves it to the front if it already exists.
  Future<void> commitSearchHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    await CacheService.instance.addSearchHistory(trimmed);
    _searchHistory.removeWhere((q) => q.toLowerCase() == trimmed.toLowerCase());
    _searchHistory.insert(0, trimmed);
    notifyListeners();
  }

  Future<void> removeSearchHistoryItem(String query) async {
    await CacheService.instance.removeSearchHistoryItem(query);
    _searchHistory.remove(query);
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    await CacheService.instance.clearSearchHistory();
    _searchHistory = [];
    notifyListeners();
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
      _favoriteIds.insert(0, trackId);
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

  /// Uploads a new cover image for [playlistId] and updates local state
  /// so it's reflected immediately everywhere the playlist is shown.
  /// Throws [ApiException] if the backend rejects the file (e.g. over
  /// the 5 MB limit, or a GIF) — callers should surface that message to
  /// the user.
  Future<void> uploadPlaylistCover({required String playlistId, required String localImagePath}) async {
    final updated = await _api.uploadPlaylistCover(playlistId: playlistId, localImagePath: localImagePath);
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      _playlists[idx] = updated;
      notifyListeners();
    }
  }

  /// Clears [playlistId]'s custom cover, reverting the UI to showing the
  /// most recently added track's cover instead (see library_screen.dart).
  Future<void> removePlaylistCover(String playlistId) async {
    final updated = await _api.removePlaylistCover(playlistId: playlistId);
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx != -1) {
      _playlists[idx] = updated;
      notifyListeners();
    }
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

  Future<String?> fetchLyrics(Track track) => _api.fetchLyrics(track);

  /// Developer-only. Uploads the lyrics text and updates the track
  /// everywhere it's currently held in memory (catalog, search results)
  /// so the lyrics panel reflects it immediately without a full reload.
  Future<void> setLyrics({required String trackId, required String lyrics}) async {
    final updated = await _api.setLyrics(trackId: trackId, lyrics: lyrics);
    _tracks = _tracks.map((t) => t.id == trackId ? updated : t).toList();
    _searchResults = _searchResults.map((t) => t.id == trackId ? updated : t).toList();
    notifyListeners();
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
