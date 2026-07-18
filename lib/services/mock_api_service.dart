import 'dart:math';
import '../models/track.dart';
import '../models/playlist.dart';
import '../models/user.dart';
import 'api_service.dart';

/// Fake backend so the UI can be built and demoed with zero server setup.
/// Public-domain-safe sample audio (SoundHelix test tracks) and random
/// placeholder cover art (picsum.photos) are used so playback actually works.
class MockApiService implements ApiService {
  MockApiService._internal() {
    _seed();
  }
  static final MockApiService instance = MockApiService._internal();

  final Random _rng = Random();
  final Duration _networkDelay = const Duration(milliseconds: 500);

  late List<Track> _tracks;
  final List<Playlist> _playlists = [];
  final Set<String> _favoriteIds = {};

  // Very naive fake "users" store, just for the demo.
  final Map<String, String> _accounts = {
    'dev@example.com': 'password123', // pre-seeded developer account
    'user@example.com': 'password123',
  };

  void _seed() {
    const samples = [
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3',
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3',
    ];
    final titles = [
      'Midnight Drive',
      'Neon Skyline',
      'Slow Sunrise',
      'Electric Bloom',
      'Paper Planes',
      'Glass Horizon',
      'Velvet Static',
      'Northern Echo',
    ];
    final artists = [
      'Aurora Waves',
      'Kilo North',
      'The Quiet Static',
      'Mira Voss',
      'Copper Room',
      'Halide',
      'Sable & Sun',
      'Vantage Point',
    ];
    _tracks = List.generate(samples.length, (i) {
      return Track(
        id: 't_$i',
        title: titles[i],
        artist: artists[i],
        album: 'Demo Sessions',
        coverUrl: 'https://picsum.photos/seed/track$i/600/600',
        audioUrl: samples[i],
        duration: Duration(minutes: 3, seconds: 10 + i * 7),
      );
    });

    _playlists.addAll([
      Playlist(
        id: 'p_chill',
        name: 'Chill Mix',
        coverUrl: 'https://picsum.photos/seed/chillmix/600/600',
        trackIds: [_tracks[1].id, _tracks[2].id, _tracks[5].id],
      ),
      Playlist(
        id: 'p_focus',
        name: 'Deep Focus',
        coverUrl: 'https://picsum.photos/seed/focusmix/600/600',
        trackIds: [_tracks[0].id, _tracks[3].id, _tracks[6].id],
      ),
    ]);

    _favoriteIds.addAll([_tracks[2].id, _tracks[4].id]);
  }

  @override
  Future<AppUser> login({required String email, required String password}) async {
    await Future.delayed(_networkDelay);
    final stored = _accounts[email.trim().toLowerCase()];
    if (stored == null || stored != password) {
      throw ApiException('Invalid email or password');
    }
    final isDeveloper = email.trim().toLowerCase() == 'dev@example.com';
    return AppUser(
      id: 'u_${email.hashCode}',
      email: email,
      displayName: email.split('@').first,
      isDeveloper: isDeveloper,
      token: 'mock-token-${_rng.nextInt(999999)}',
    );
  }

  @override
  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await Future.delayed(_networkDelay);
    final key = email.trim().toLowerCase();
    if (_accounts.containsKey(key)) {
      throw ApiException('An account with this email already exists');
    }
    _accounts[key] = password;
    return AppUser(
      id: 'u_${email.hashCode}',
      email: email,
      displayName: displayName.isEmpty ? email.split('@').first : displayName,
      isDeveloper: false,
      token: 'mock-token-${_rng.nextInt(999999)}',
    );
  }

  @override
  Future<List<Track>> fetchTracks() async {
    await Future.delayed(_networkDelay);
    return List.unmodifiable(_tracks);
  }

  @override
  Future<List<Track>> searchTracks(String query) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return _tracks
        .where((t) =>
            t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q) ||
            t.album.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<Track> uploadTrack({
    required String title,
    required String artist,
    required String album,
    required String localAudioPath,
    String? localCoverPath,
  }) async {
    await Future.delayed(_networkDelay);
    // In production this would upload the file bytes to the Python backend,
    // which would then store them in Yandex Object Storage and return the
    // resulting public URL. Here we just reuse the local file path so the
    // track can still be played back on-device.
    final track = Track(
      id: 't_local_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      artist: artist,
      album: album.isEmpty ? 'Uploaded' : album,
      coverUrl: localCoverPath ?? 'https://picsum.photos/seed/${title.hashCode}/600/600',
      audioUrl: localAudioPath,
      duration: const Duration(minutes: 3),
      uploadedLocally: true,
    );
    _tracks.insert(0, track);
    return track;
  }

  @override
  Future<List<Playlist>> fetchPlaylists() async {
    await Future.delayed(_networkDelay);
    return List.unmodifiable(_playlists);
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    await Future.delayed(_networkDelay);
    final playlist = Playlist(
      id: 'p_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      coverUrl: 'https://picsum.photos/seed/${name.hashCode}/600/600',
      trackIds: [],
    );
    _playlists.add(playlist);
    return playlist;
  }

  @override
  Future<void> addTrackToPlaylist({required String playlistId, required String trackId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return;
    final playlist = _playlists[idx];
    if (!playlist.trackIds.contains(trackId)) {
      _playlists[idx] = playlist.copyWith(trackIds: [...playlist.trackIds, trackId]);
    }
  }

  @override
  Future<void> removeTrackFromPlaylist({required String playlistId, required String trackId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return;
    final playlist = _playlists[idx];
    _playlists[idx] = playlist.copyWith(
      trackIds: playlist.trackIds.where((id) => id != trackId).toList(),
    );
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _playlists.removeWhere((p) => p.id == playlistId);
  }

  @override
  Future<List<String>> fetchFavoriteIds() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _favoriteIds.toList();
  }

  @override
  Future<void> setFavorite({required String trackId, required bool favorite}) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (favorite) {
      _favoriteIds.add(trackId);
    } else {
      _favoriteIds.remove(trackId);
    }
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
