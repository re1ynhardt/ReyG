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
///   POST   /playlists/{id}/cover multipart(cover)      -> playlist json (max 5 MB, no GIFs, enforce server-side too)
///   DELETE /playlists/{id}/cover                        -> playlist json
///   GET    /favorites                                 -> [track_id]
///   PUT    /favorites/{trackId}  {favorite: bool}      -> 204
///   POST   /account/avatar      multipart(avatar)      -> user json (max 5 MB, enforce server-side too)
///   GET    /community/users                              -> [user json, ...] (tokens blank)
///   GET    /community/users/{id}/liked_tracks              -> [track json, ...]
///   GET    /community/users/{id}/playlists                -> [playlist json, ...]
///   DELETE /community/users/{id}                          -> 204 (developer-only)
///   GET    /community/favorite_users                       -> [user_id, ...]
///   PUT    /community/favorite_users/{id}  {favorite: bool} -> 204
///   PUT    /account/privacy     {privacy: "all"|"favorites"|"none"} -> user json
///   GET    /community/users/{id}/can_view                  -> {can_view: bool}
///   PUT    /account/password    {password: string}          -> 204 (no old password required)
///   GET    /tracks/{id}/lyrics                          -> {lyrics: string} or 404 if none
///   PUT    /tracks/{id}/lyrics  {lyrics: string}        -> track json (developer-only)
///   POST   /tracks/{id}/hashtags {hashtag: string}      -> track json
///   DELETE /tracks/{id}/hashtags/{hashtag}              -> track json (admin-only)
///   GET    /featured_tags                               -> ["tag1","tag2","tag3","tag4"]
///   PUT    /featured_tags       {tags: [t1,t2,t3,t4]}    -> ["tag1","tag2","tag3","tag4"] (developer-only)
///   GET    /artists/avatars                              -> {"Artist Name": "url", ...}
///   POST   /artists/{artist}/avatar multipart(avatar)    -> {"avatar_url": "..."} (developer-only, max 5 MB, enforce server-side too)
///   DELETE /artists/{artist}/avatar                      -> 204 (developer-only)
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
  void restoreSession(AppUser user) {
    authToken = user.token;
  }

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
  Future<void> deleteTrack(String trackId) async {
    final res = await http.delete(_u('/tracks/$trackId'), headers: _headers);
    _throwIfError(res);
  }

  @override
  Future<String?> fetchLyrics(Track track) async {
    final res = await http.get(_u('/tracks/${track.id}/lyrics'), headers: _headers);
    if (res.statusCode == 404) return null;
    _throwIfError(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['lyrics'] as String?;
  }

  @override
  Future<Track> setLyrics({required String trackId, required String lyrics}) async {
    final res = await http.put(_u('/tracks/$trackId/lyrics'),
        headers: _headers, body: jsonEncode({'lyrics': lyrics}));
    _throwIfError(res);
    return Track.fromJson(jsonDecode(res.body));
  }

  @override
  Future<Track> addHashtag({required String trackId, required String hashtag}) async {
    final tag = hashtag.trim().toLowerCase();
    if (!Track.isValidHashtag(tag)) {
      throw ApiException('Hashtags can only contain lowercase English letters and numbers');
    }
    final res = await http.post(_u('/tracks/$trackId/hashtags'),
        headers: _headers, body: jsonEncode({'hashtag': tag}));
    _throwIfError(res);
    return Track.fromJson(jsonDecode(res.body));
  }

  @override
  Future<Track> removeHashtag({required String trackId, required String hashtag}) async {
    final res = await http.delete(_u('/tracks/$trackId/hashtags/${Uri.encodeComponent(hashtag)}'), headers: _headers);
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
  Future<Playlist> uploadPlaylistCover({required String playlistId, required String localImagePath}) async {
    final request = http.MultipartRequest('POST', _u('/playlists/$playlistId/cover'));
    if (authToken != null) request.headers['Authorization'] = 'Bearer $authToken';
    request.files.add(await http.MultipartFile.fromPath('cover', localImagePath));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    _throwIfError(res);
    return Playlist.fromJson(jsonDecode(res.body));
  }

  @override
  Future<Playlist> removePlaylistCover({required String playlistId}) async {
    final res = await http.delete(_u('/playlists/$playlistId/cover'), headers: _headers);
    _throwIfError(res);
    return Playlist.fromJson(jsonDecode(res.body));
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

  @override
  Future<AppUser> uploadAvatar(String localImagePath) async {
    final request = http.MultipartRequest('POST', _u('/account/avatar'));
    if (authToken != null) request.headers['Authorization'] = 'Bearer $authToken';
    request.files.add(await http.MultipartFile.fromPath('avatar', localImagePath));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    _throwIfError(res);
    return AppUser.fromJson(jsonDecode(res.body));
  }

  @override
  Future<List<AppUser>> fetchAllUsers() async {
    final res = await http.get(_u('/community/users'), headers: _headers);
    _throwIfError(res);
    return (jsonDecode(res.body) as List).map((e) => AppUser.fromJson(e)).toList();
  }

  @override
  Future<List<Track>> fetchFavoriteTracksByUser(String userId) async {
    final res = await http.get(_u('/community/users/$userId/liked_tracks'), headers: _headers);
    _throwIfError(res);
    return (jsonDecode(res.body) as List).map((e) => Track.fromJson(e)).toList();
  }

  @override
  Future<List<Playlist>> fetchPlaylistsByUser(String userId) async {
    final res = await http.get(_u('/community/users/$userId/playlists'), headers: _headers);
    _throwIfError(res);
    return (jsonDecode(res.body) as List).map((e) => Playlist.fromJson(e)).toList();
  }

  @override
  Future<void> deleteUserAccount(String userId) async {
    final res = await http.delete(_u('/community/users/$userId'), headers: _headers);
    _throwIfError(res);
  }

  @override
  Future<void> setUserPassword({required String userId, required String newPassword}) async {
    final res = await http.put(
      _u('/community/users/$userId/password'),
      headers: _headers,
      body: jsonEncode({'password': newPassword}),
    );
    _throwIfError(res);
  }

  @override
  Future<List<String>> fetchFavoriteUserIds() async {
    final res = await http.get(_u('/community/favorite_users'), headers: _headers);
    _throwIfError(res);
    return (jsonDecode(res.body) as List).map((e) => e as String).toList();
  }

  @override
  Future<void> setFavoriteUser({required String userId, required bool favorite}) async {
    final res = await http.put(
      _u('/community/favorite_users/$userId'),
      headers: _headers,
      body: jsonEncode({'favorite': favorite}),
    );
    _throwIfError(res);
  }

  @override
  Future<AppUser> setLikesPrivacy(String privacy) async {
    final res = await http.put(
      _u('/account/privacy'),
      headers: _headers,
      body: jsonEncode({'privacy': privacy}),
    );
    _throwIfError(res);
    return AppUser.fromJson(jsonDecode(res.body));
  }

  @override
  Future<bool> canViewUserLibrary(String userId) async {
    final res = await http.get(_u('/community/users/$userId/can_view'), headers: _headers);
    _throwIfError(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['can_view'] as bool? ?? false;
  }

  @override
  Future<void> setPassword(String newPassword) async {
    final res = await http.put(
      _u('/account/password'),
      headers: _headers,
      body: jsonEncode({'password': newPassword}),
    );
    _throwIfError(res);
  }

  @override
  Future<AppUser> setBio(String bio) async {
    final res = await http.put(
      _u('/account/bio'),
      headers: _headers,
      body: jsonEncode({'bio': bio}),
    );
    _throwIfError(res);
    return AppUser.fromJson(jsonDecode(res.body));
  }

  @override
  Future<List<String>> fetchFeaturedTags() async {
    final res = await http.get(_u('/featured_tags'), headers: _headers);
    _throwIfError(res);
    return (jsonDecode(res.body) as List).map((e) => e as String).toList();
  }

  @override
  Future<List<String>> setFeaturedTags(List<String> tags) async {
    final res = await http.put(_u('/featured_tags'),
        headers: _headers, body: jsonEncode({'tags': tags}));
    _throwIfError(res);
    return (jsonDecode(res.body) as List).map((e) => e as String).toList();
  }

  @override
  Future<Map<String, String>> fetchArtistAvatars() async {
    final res = await http.get(_u('/artists/avatars'), headers: _headers);
    _throwIfError(res);
    return (jsonDecode(res.body) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String));
  }

  @override
  Future<String> uploadArtistAvatar({required String artist, required String localImagePath}) async {
    final request = http.MultipartRequest('POST', _u('/artists/${Uri.encodeComponent(artist)}/avatar'));
    if (authToken != null) request.headers['Authorization'] = 'Bearer $authToken';
    request.files.add(await http.MultipartFile.fromPath('avatar', localImagePath));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    _throwIfError(res);
    return (jsonDecode(res.body) as Map<String, dynamic>)['avatar_url'] as String;
  }

  @override
  Future<void> removeArtistAvatar(String artist) async {
    final res = await http.delete(_u('/artists/${Uri.encodeComponent(artist)}/avatar'), headers: _headers);
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