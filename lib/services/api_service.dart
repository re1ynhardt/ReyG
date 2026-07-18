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

  // --- Playlists --------------------------------------------------------
  Future<List<Playlist>> fetchPlaylists();
  Future<Playlist> createPlaylist(String name);
  Future<void> addTrackToPlaylist({required String playlistId, required String trackId});
  Future<void> removeTrackFromPlaylist({required String playlistId, required String trackId});
  Future<void> deletePlaylist(String playlistId);

  // --- Favorites ----------------------------------------------------------
  Future<List<String>> fetchFavoriteIds();
  Future<void> setFavorite({required String trackId, required bool favorite});
}
