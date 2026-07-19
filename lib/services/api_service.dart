import '../models/track.dart';
import '../models/playlist.dart';
import '../models/user.dart';

/// Every screen in the app talks to the backend ONLY through this
/// interface. Today [MockApiService] answers with fake in-memory data.
/// Later, drop in [RemoteApiService] (see remote_api_service.dart) which
/// hits your real Python backend over HTTP — no UI code needs to change.
abstract class ApiService {
  // --- Auth -----------------------------------------------------------
  Future<AppUser> login({required String email, required String password});
  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
  });

  /// Called once after a session is restored from local storage (app
  /// reopened, user already logged in previously) so the backend knows
  /// who's "current" without requiring another login. Implementations
  /// that don't need this (e.g. the mock) can leave it a no-op.
  void restoreSession(AppUser user);

  // --- Tracks -----------------------------------------------------------
  Future<List<Track>> fetchTracks();
  Future<List<Track>> searchTracks(String query);

  /// Requirement #11: developer accounts can push a track straight from
  /// the app instead of using the admin script / server.
  Future<Track> uploadTrack({
    required String title,
    required String artist,
    required String album,
    required String localAudioPath,
    String? localCoverPath,
  });

  /// Developer-only: permanently removes a track from the catalog (and,
  /// where possible, the underlying audio/cover files too), plus every
  /// reference to it in playlists and favorites, everywhere in the app.
  Future<void> deleteTrack(String trackId);

  /// Fetches the lyrics text for [track], or returns null if none has
  /// been added yet. Lyrics are stored as a text object in Yandex
  /// Storage — this reads that object (lazily, only when the lyrics
  /// panel is opened), not a database.
  Future<String?> fetchLyrics(Track track);

  /// Developer-only: uploads/overwrites the lyrics text for a track and
  /// returns the updated [Track] (with `lyricsUrl` populated).
  Future<Track> setLyrics({required String trackId, required String lyrics});

  /// Adds [hashtag] (without the leading '#') to [trackId]'s hashtags and
  /// returns the updated [Track]. Any signed-in user may call this.
  /// Implementations enforce [Track.maxHashtags] and
  /// [Track.maxHashtagLength] server-side too, as a safety net behind
  /// whatever the UI already checks before calling this.
  Future<Track> addHashtag({required String trackId, required String hashtag});

  /// Removes [hashtag] from [trackId]'s hashtags and returns the updated
  /// [Track]. Admin/developer accounts only — implementations reject this
  /// for regular users.
  Future<Track> removeHashtag({required String trackId, required String hashtag});

  // --- Playlists --------------------------------------------------------
  Future<List<Playlist>> fetchPlaylists();
  Future<Playlist> createPlaylist(String name);
  Future<void> addTrackToPlaylist({required String playlistId, required String trackId});
  Future<void> removeTrackFromPlaylist({required String playlistId, required String trackId});
  Future<void> deletePlaylist(String playlistId);

  /// Uploads a custom cover image for a playlist owned by the current
  /// user and returns the updated [Playlist] (with the new `coverUrl`
  /// populated). Callers are expected to enforce the 5 MB size limit and
  /// reject GIFs before calling this — see [ApiException] thrown by
  /// implementations that also enforce these rules server-side/storage-side
  /// as a safety net.
  Future<Playlist> uploadPlaylistCover({required String playlistId, required String localImagePath});

  /// Clears a playlist's custom cover (`coverUrl` goes back to `''`), so
  /// the UI falls back to showing the most recently added track's cover
  /// instead. Returns the updated [Playlist].
  Future<Playlist> removePlaylistCover({required String playlistId});

  // --- Favorites ----------------------------------------------------------
  Future<List<String>> fetchFavoriteIds();
  Future<void> setFavorite({required String trackId, required bool favorite});

  // --- Account ------------------------------------------------------------
  /// Uploads a custom avatar image for the current user and returns the
  /// updated [AppUser] (with the new `avatarUrl` populated). Callers are
  /// expected to enforce the 5 MB size limit before calling this — see
  /// [ApiException] thrown by implementations that also enforce it
  /// server-side/storage-side as a safety net.
  Future<AppUser> uploadAvatar(String localImagePath);

  // --- Featured tags (Home screen) ----------------------------------------
  /// The 4 hashtags currently pinned to the Home screen, in display order.
  /// Same list for every account — always length 4, with `''` marking an
  /// unset slot. Implementations should return 4 empty strings before any
  /// developer has configured them.
  Future<List<String>> fetchFeaturedTags();

  /// Developer-only: overwrites the 4 featured-tag slots (pass `''` to
  /// clear a slot) and returns the resulting list. Implementations reject
  /// this for non-developer accounts and validate each non-empty tag the
  /// same way [addHashtag] does.
  Future<List<String>> setFeaturedTags(List<String> tags);
}
