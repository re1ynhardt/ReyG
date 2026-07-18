import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/track.dart';
import '../models/playlist.dart';
import '../models/user.dart';
import 'api_service.dart';

/// Real implementation that talks to your Python backend.
///
/// HOW TO SWITCH FROM MOCK TO REAL BACKEND:
///   1. Point `baseUrl` at your server (see backend_reference.py for the
///      matching single-file Flask reference implementation).
///   2. In `lib/main.dart`, replace:
///        final ApiService api = MockApiService.instance;
///      with:
///        final ApiService api = RemoteApiService(baseUrl: 'https://your-server.com');
///   3. That's it — every screen already talks only to `ApiService`.
///
/// Expected REST contract (adjust paths/fields to taste, keep it simple):
///   POST   /auth/login          {email, password} -> user json
///   POST   /auth/register       {email, password, display_name} -> user json
///   GET    /tracks                                  -> [track json]
///   GET    /tracks/search?q=...                      -> [track json]
///   POST   /tracks/upload       multipart(audio, cover, title, artist, album) -> track json
///   GET    /playlists                                -> [playlist json]
///   POST   /playlists           {name}               -> playlist json
///   POST   /playlists/{id}/tracks       {track_id}    -> 204
///   DELETE /playlists/{id}/tracks/{trackId}           -> 204
///   DELETE /playlists/{id}                            -> 204
///   GET    /favorites                                 -> [track_id]
///   PUT    /favorites/{trackId}  {favorite: bool}      -> 204
class RemoteApiService implements ApiService {
  RemoteApiService({required this.baseUrl, this.authToken});

  final String baseUrl;
  String? authToken;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  @override
  Future<AppUser> login({required String email, required String password}) async {
    final res = await http.post(_u('/auth/login'),
        headers: _headers, body: jsonEncode({'email': email, 'password': password}));
    _throwIfError(res);
    final user = AppUser.fromJson(jsonDecode(res.body));
    authToken = user.token;
    return user;
  }

  @override
  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final res = await http.post(_u('/auth/register'),
        headers: _headers,
        body: jsonEncode({'email': email, 'password': password, 'display_name': displayName}));
    _throwIfError(res);
    final user = AppUser.fromJson(jsonDecode(res.body));
    authToken = user.token;
    return user;
  }

  @override
  Future<List<Track>> fetchTracks() async {
    final res = await http.get(_u('/tracks'), headers: _headers);
    _throwIfError(res);
    return (jsonDecode(res.body) as List).map((e) => Track.fromJson(e)).toList();
  }

  @override
  Future<List<Track>> searchTracks(String query) async {
    final res = await http.get(_u('/tracks/search?q=${Uri.encodeQueryComponent(query)}'), headers: _headers);
    _throwIfError(res);
    return (jsonDecode(res.body) as List).map((e) => Track.fromJson(e)).toList();
  }

  @override
  Future<Track> uploadTrack({
    required String title,
    required String artist,
    required String album,
    required String localAudioPath,
    String? localCoverPath,
  }) async {
    final request = http.MultipartRequest('POST', _u('/tracks/upload'));
    if (authToken != null) request.headers['Authorization'] = 'Bearer $authToken';
    request.fields['title'] = title;
    request.fields['artist'] = artist;
    request.fields['album'] = album;
    request.files.add(await http.MultipartFile.fromPath('audio', localAudioPath));
    if (localCoverPath != null) {
      request.files.add(await http.MultipartFile.fromPath('cover', localCoverPath));
    }
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    _throwIfError(res);
    return Track.fromJson(jsonDecode(res.body));
  }

  @override
  Future<List<Playlist>> fetchPlaylists() async {
    final res = await http.get(_u('/playlists'), headers: _headers);
    _throwIfError(res);
    return (jsonDecode(res.body) as List).map((e) => Playlist.fromJson(e)).toList();
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    final res = await http.post(_u('/playlists'), headers: _headers, body: jsonEncode({'name': name}));
    _throwIfError(res);
    return Playlist.fromJson(jsonDecode(res.body));
  }

  @override
  Future<void> addTrackToPlaylist({required String playlistId, required String trackId}) async {
    final res = await http.post(_u('/playlists/$playlistId/tracks'),
        headers: _headers, body: jsonEncode({'track_id': trackId}));
    _throwIfError(res);
  }

  @override
  Future<void> removeTrackFromPlaylist({required String playlistId, required String trackId}) async {
    final res = await http.delete(_u('/playlists/$playlistId/tracks/$trackId'), headers: _headers);
    _throwIfError(res);
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    final res = await http.delete(_u('/playlists/$playlistId'), headers: _headers);
    _throwIfError(res);
  }

  @override
  Future<List<String>> fetchFavoriteIds() async {
    final res = await http.get(_u('/favorites'), headers: _headers);
    _throwIfError(res);
    return (jsonDecode(res.body) as List).map((e) => e as String).toList();
  }

  @override
  Future<void> setFavorite({required String trackId, required bool favorite}) async {
    final res = await http.put(_u('/favorites/$trackId'),
        headers: _headers, body: jsonEncode({'favorite': favorite}));
    _throwIfError(res);
  }

  void _throwIfError(http.Response res) {
    if (res.statusCode >= 400) {
      throw ApiException('Server error ${res.statusCode}: ${res.body}');
    }
  }
  
}
class ApiException implements Exception {
  final String message;
  
  ApiException(this.message);

  @override
  String toString() => message;
}