import 'dart:math';
import 'package:flutter/foundation.dart';
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
  /// The 4 developer-picked hashtags shown on Home, in slot order — the
  /// same for every account. `''` marks an unset slot.
  List<String> _featuredTags = List<String>.filled(4, '');
  /// Developer-set circular avatar URLs, keyed by exact artist name. See
  /// [avatarForArtist] for the fallback used when an artist has none.
  Map<String, String> _artistAvatars = {};

  List<Track> _searchResults = [];
  bool _searching = false;
  bool _loading = false;
  List<String> _searchHistory = [];

  // Recommendations cache: recomputing on every rebuild would reshuffle
  // the list (it's randomized) even when nothing actually changed, so we
  // only recompute when the seed (the last 5 played track ids, in order)
  // is different from the last computation, or the catalog was reloaded.
  List<Track>? _cachedRecommendations;
  List<String> _cachedRecommendationsSeed = const [];

  List<Track> get tracks => _tracks;
  List<Playlist> get playlists => _playlists;
  Set<String> get favoriteIds => _favoriteIds.toSet();
  List<Track> get searchResults => _searchResults;
  bool get searching => _searching;
  bool get loading => _loading;
  List<String> get searchHistory => _searchHistory;
  /// Always length 4; `''` for any slot the developers haven't set yet.
  List<String> get featuredTags => _featuredTags;
  /// Developer-set artist avatar URLs, keyed by exact artist name.
  Map<String, String> get artistAvatars => _artistAvatars;

  List<Track> get favoriteTracks {
    final map = {for (final t in _tracks) t.id: t};
    return _favoriteIds.map((id) => map[id]).whereType<Track>().toList();
  }

  List<Track> get recentlyPlayedTracks {
    final map = {for (final t in _tracks) t.id: t};
    return _recentlyPlayedIds.map((id) => map[id]).whereType<Track>().toList();
  }

  /// The most recently uploaded track carrying [tag], or null if no track
  /// has it (or [tag] is empty). [_tracks] is already newest-first (the
  /// backend returns tracks ordered by upload time, newest first — see
  /// `list_tracks()` in backend_reference.py), so the first match wins.
  Track? latestTrackForTag(String tag) {
    if (tag.isEmpty) return null;
    for (final t in _tracks) {
      if (t.hashtags.contains(tag)) return t;
    }
    return null;
  }

  /// Every track carrying [tag], newest-upload-first (same ordering as
  /// [tracks] and every other track list in the app).
  List<Track> tracksForTag(String tag) => _tracks.where((t) => t.hashtags.contains(tag)).toList();

  /// Circular-avatar image URL to show for [artist]: the developer-set
  /// avatar if one has been set, otherwise the cover art of that
  /// artist's most recently uploaded track — [_tracks] is already
  /// newest-first, so the first match wins (same fallback rule
  /// [ArtistTracksScreen] already used for its own header background).
  /// Returns `''` if the artist has no custom avatar and no tracks
  /// (e.g. their last track was deleted after the avatar was cleared).
  String avatarForArtist(String artist) {
    final custom = _artistAvatars[artist];
    if (custom != null && custom.isNotEmpty) return custom;
    for (final t in _tracks) {
      if (t.artist == artist) return t.coverUrl;
    }
    return '';
  }

  /// Whether [artist] has a developer-set avatar (as opposed to falling
  /// back to a track cover) — drives whether "remove avatar" is shown.
  bool hasCustomArtistAvatar(String artist) => (_artistAvatars[artist] ?? '').isNotEmpty;

  /// Distinct artist names in the catalog whose name contains [query]
  /// (case-insensitive), newest-track-first. Used to show the small
  /// "artists" block above track results on the Search screen. Returns
  /// nothing for hashtag searches (a leading '#'), since those already
  /// have their own dedicated matching behavior in [search].
  List<String> searchArtists(String query) {
    final term = query.trim().toLowerCase();
    if (term.isEmpty || term.startsWith('#')) return [];
    final seen = <String>{};
    final result = <String>[];
    for (final t in _tracks) {
      if (seen.contains(t.artist)) continue;
      if (t.artist.toLowerCase().contains(term)) {
        seen.add(t.artist);
        result.add(t.artist);
      }
    }
    return result;
  }

  /// Recommendations tab (requirement: home + recommendations swipe
  /// widget). Built from the last 5 tracks played on this device (from
  /// the on-device cache, newest first — [_recentlyPlayedIds]): for each
  /// of those tracks' hashtags (up to 4 each), 2 random tracks carrying
  /// that hashtag are pulled from the full catalog. A track already
  /// picked earlier in this pass is never picked again, even if it
  /// matches another hashtag, and the 5 seed tracks themselves are never
  /// recommended back. Max size is 5 * 4 * 2 = 40.
  ///
  /// The selection is randomized, so it's cached against the seed (the
  /// ordered list of the last 5 played ids) and only recomputed when
  /// that seed changes or the catalog is reloaded — otherwise every
  /// rebuild (e.g. a player tick) would reshuffle the list under the
  /// user's thumb.
  List<Track> get recommendedTracks {
    final seedIds = _recentlyPlayedIds.take(5).toList();
    if (_cachedRecommendations != null && listEquals(_cachedRecommendationsSeed, seedIds)) {
      return _cachedRecommendations!;
    }

    final trackMap = {for (final t in _tracks) t.id: t};
    final seeds = seedIds.map((id) => trackMap[id]).whereType<Track>().toList();
    final excluded = seedIds.toSet(); // never recommend a just-played track back
    final random = Random();
    final result = <Track>[];

    for (final seed in seeds) {
      for (final tag in seed.hashtags.take(Track.maxHashtags)) {
        if (tag.isEmpty) continue;
        final candidates = _tracks
            .where((t) => t.hashtags.contains(tag) && !excluded.contains(t.id))
            .toList()
          ..shuffle(random);
        for (final pick in candidates.take(2)) {
          excluded.add(pick.id);
          result.add(pick);
        }
      }
    }

    _cachedRecommendationsSeed = seedIds;
    _cachedRecommendations = result;
    return result;
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
        _api.fetchFeaturedTags(),
        _api.fetchArtistAvatars(),
      ]);
      _tracks = results[0] as List<Track>;
      _playlists = results[1] as List<Playlist>;
      _favoriteIds = (results[2] as List<String>).reversed.toList();
      _recentlyPlayedIds = results[3] as List<String>;
      _searchHistory = results[4] as List<String>;
      _featuredTags = results[5] as List<String>;
      _artistAvatars = results[6] as Map<String, String>;
      _cachedRecommendations = null; // catalog changed — recompute next access
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

  /// Any signed-in user can call this. Throws [ApiException] if the
  /// backend rejects it (over the 4-hashtag cap, over 10 characters, or a
  /// duplicate) — callers should surface that message to the user.
  Future<void> addHashtag({required String trackId, required String hashtag}) async {
    final updated = await _api.addHashtag(trackId: trackId, hashtag: hashtag);
    _tracks = _tracks.map((t) => t.id == trackId ? updated : t).toList();
    _searchResults = _searchResults.map((t) => t.id == trackId ? updated : t).toList();
    notifyListeners();
  }

  /// Admin/developer accounts only — throws [ApiException] for anyone
  /// else, which the UI is expected to have already prevented by hiding
  /// the delete affordance from non-admins in the first place.
  Future<void> removeHashtag({required String trackId, required String hashtag}) async {
    final updated = await _api.removeHashtag(trackId: trackId, hashtag: hashtag);
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

  /// Developer-only. Updates the 4 hashtags featured on every account's
  /// Home screen. Throws [ApiException] for non-developer accounts — the
  /// UI is expected to have already hidden this behind an isDeveloper
  /// check, same as [removeHashtag].
  Future<void> setFeaturedTags(List<String> tags) async {
    final updated = await _api.setFeaturedTags(tags);
    _featuredTags = updated;
    notifyListeners();
  }

  /// Developer-only. Uploads a new avatar image for [artist] and updates
  /// local state so it's reflected immediately everywhere that artist's
  /// avatar is shown (Search results block, their tracks screen).
  /// Throws [ApiException] if the backend rejects it (non-developer
  /// account, over the 5 MB limit, etc.) — callers should surface that
  /// message to the user.
  Future<void> uploadArtistAvatar({required String artist, required String localImagePath}) async {
    final url = await _api.uploadArtistAvatar(artist: artist, localImagePath: localImagePath);
    _artistAvatars = {..._artistAvatars, artist: url};
    notifyListeners();
  }

  /// Developer-only. Clears [artist]'s custom avatar, reverting the UI
  /// to falling back on their most recent track cover again (see
  /// [avatarForArtist]).
  Future<void> removeArtistAvatar(String artist) async {
    await _api.removeArtistAvatar(artist);
    _artistAvatars = {..._artistAvatars}..remove(artist);
    notifyListeners();
  }
}
