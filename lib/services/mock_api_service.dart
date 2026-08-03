import 'dart:math';
import '../models/track.dart';
import '../models/playlist.dart';
import '../models/user.dart';
import '../models/app_notification.dart';
import '../models/message.dart';
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
  final Set<String> _favoriteUserIds = {};
  final Map<String, String> _lyrics = {};
  /// The 4 developer-picked tags shown on Home, in slot order. `''` means
  /// that slot hasn't been set yet.
  List<String> _featuredTags = List<String>.filled(4, '');
  /// Developer-set artist avatar URLs, keyed by exact artist name.
  final Map<String, String> _artistAvatars = {};

  // Very naive fake "users" store, just for the demo.
  final Map<String, String> _accounts = {
    'dev@example.com': 'password123', // pre-seeded developer account
    'support@example.com': 'password123', // pre-seeded support account
    'artist@example.com': 'password123', // pre-seeded "исполнитель" (performer) account
    'user@example.com': 'password123',
  };

  /// Emails that get the "исполнитель" (performer/artist) role — same
  /// track-management rights as developers (upload tracks, delete
  /// tracks, delete hashtags) without the rest of the developer-only
  /// surface. Mirrors [YandexStorageConfig.performerEmails].
  static const Set<String> _performerEmails = {'artist@example.com'};

  /// Emails that get the "поддержка" (support) role — exactly the same
  /// rights as developer accounts. Mirrors
  /// [YandexStorageConfig.supportEmails].
  static const Set<String> _supportEmails = {'support@example.com'};

  @override
  void restoreSession(AppUser user) {
    _currentMockUser = user;
  }

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
    final user = AppUser(
      id: 'u_${email.hashCode}',
      email: email,
      displayName: email.split('@').first,
      isDeveloper: isDeveloper,
      isPerformer: _performerEmails.contains(email.trim().toLowerCase()),
      isSupport: _supportEmails.contains(email.trim().toLowerCase()),
      token: 'mock-token-${_rng.nextInt(999999)}',
    );
    _currentMockUser = user;
    return user;
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
    final user = AppUser(
      id: 'u_${email.hashCode}',
      email: email,
      displayName: displayName.isEmpty ? email.split('@').first : displayName,
      isDeveloper: false,
      token: 'mock-token-${_rng.nextInt(999999)}',
    );
    _currentMockUser = user;
    return user;
  }

  @override
  Future<List<Track>> fetchTracks() async {
    await Future.delayed(_networkDelay);
    return List.unmodifiable(_tracks);
  }

  @override
  Future<List<Track>> searchTracks(String query) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final raw = query.trim().toLowerCase();
    if (raw.isEmpty) return [];
    // A leading '#' (e.g. "#phonk") searches hashtags only. Otherwise
    // fall back to the regular title/artist/album search — but still
    // include hashtag matches, so a plain "phonk" also surfaces tracks
    // tagged #phonk even if the word appears nowhere else on the track.
    final isHashtagSearch = raw.startsWith('#');
    final term = isHashtagSearch ? raw.substring(1) : raw;
    if (term.isEmpty) return [];
    return _tracks.where((t) {
      final hashtagMatch = t.hashtags.any((tag) => tag.contains(term));
      if (isHashtagSearch) return hashtagMatch;
      return t.title.toLowerCase().contains(term) ||
          t.artist.toLowerCase().contains(term) ||
          t.album.toLowerCase().contains(term) ||
          hashtagMatch;
    }).toList();
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
    final current = _currentMockUser;
    if (current == null || (!current.isDeveloper && !current.isPerformer && !current.isSupport)) {
      throw ApiException('Only developer, support, or performer accounts can upload tracks');
    }
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
  Future<void> deleteTrack(String trackId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final current = _currentMockUser;
    if (current == null || (!current.isDeveloper && !current.isPerformer && !current.isSupport)) {
      throw ApiException('Only developer, support, or performer accounts can delete tracks');
    }
    _tracks.removeWhere((t) => t.id == trackId);
    _favoriteIds.remove(trackId);
    _lyrics.remove(trackId);
    for (var i = 0; i < _playlists.length; i++) {
      _playlists[i] = _playlists[i].copyWith(
        trackIds: _playlists[i].trackIds.where((id) => id != trackId).toList(),
      );
    }
  }

  @override
  Future<String?> fetchLyrics(Track track) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _lyrics[track.id];
  }

  @override
  Future<Track> setLyrics({required String trackId, required String lyrics}) async {
    await Future.delayed(_networkDelay);
    final current = _currentMockUser;
    if (current == null || (!current.isDeveloper && !current.isSupport && !current.isPerformer)) {
      throw ApiException('Only developer, support, or performer accounts can add lyrics');
    }
    _lyrics[trackId] = lyrics;
    final idx = _tracks.indexWhere((t) => t.id == trackId);
    if (idx == -1) throw ApiException('Track not found');
    final updated = _tracks[idx].copyWith(lyricsUrl: 'mock://lyrics/$trackId');
    _tracks[idx] = updated;
    return updated;
  }

  @override
  Future<Track> addHashtag({required String trackId, required String hashtag}) async {
    await Future.delayed(_networkDelay);
    final tag = hashtag.trim().toLowerCase();
    if (tag.isEmpty) throw ApiException('Hashtag cannot be empty');
    if (tag.length > Track.maxHashtagLength) {
      throw ApiException('Hashtag must be ${Track.maxHashtagLength} characters or fewer');
    }
    if (!Track.isValidHashtag(tag)) {
      throw ApiException('Hashtags can only contain lowercase English letters and numbers');
    }
    final idx = _tracks.indexWhere((t) => t.id == trackId);
    if (idx == -1) throw ApiException('Track not found');
    final tags = _tracks[idx].hashtags;
    if (tags.contains(tag)) throw ApiException('That hashtag is already on this track');
    if (tags.length >= Track.maxHashtags) {
      throw ApiException('A track can have at most ${Track.maxHashtags} hashtags');
    }
    final updated = _tracks[idx].copyWith(hashtags: [...tags, tag]);
    _tracks[idx] = updated;
    return updated;
  }

  @override
  Future<Track> removeHashtag({required String trackId, required String hashtag}) async {
    await Future.delayed(_networkDelay);
    final current = _currentMockUser;
    if (current == null || (!current.isDeveloper && !current.isPerformer && !current.isSupport)) {
      throw ApiException('Only developer, support, or performer accounts can remove hashtags');
    }
    final idx = _tracks.indexWhere((t) => t.id == trackId);
    if (idx == -1) throw ApiException('Track not found');
    final tag = hashtag.trim().toLowerCase();
    final updated = _tracks[idx].copyWith(hashtags: _tracks[idx].hashtags.where((t) => t != tag).toList());
    _tracks[idx] = updated;
    return updated;
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
  Future<Playlist> renamePlaylist({required String playlistId, required String newName}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw ApiException('Playlist name cannot be empty');
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) throw ApiException('Playlist not found');
    final updated = _playlists[idx].copyWith(name: trimmed);
    _playlists[idx] = updated;
    return updated;
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
  Future<Playlist> uploadPlaylistCover({required String playlistId, required String localImagePath}) async {
    await Future.delayed(_networkDelay);
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) throw ApiException('Playlist not found');
    // In production this uploads the bytes to Yandex Object Storage and
    // returns the resulting public URL. Here we just reuse the local file
    // path so the picked image can still be previewed on-device.
    final updated = _playlists[idx].copyWith(coverUrl: localImagePath);
    _playlists[idx] = updated;
    return updated;
  }

  @override
  Future<Playlist> removePlaylistCover({required String playlistId}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) throw ApiException('Playlist not found');
    final updated = _playlists[idx].copyWith(coverUrl: '');
    _playlists[idx] = updated;
    return updated;
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

  AppUser? _currentMockUser;

  @override
  Future<AppUser> uploadAvatar(String localImagePath) async {
    await Future.delayed(_networkDelay);
    // In production this uploads the bytes to Yandex Object Storage and
    // returns the resulting public URL. Here we just reuse the local file
    // path so the picked image can still be previewed on-device.
    final current = _currentMockUser;
    if (current == null) throw ApiException('Not logged in');
    final updated = current.copyWith(avatarUrl: localImagePath);
    _currentMockUser = updated;
    return updated;
  }

  @override
  Future<AppUser> uploadBanner(String localImagePath) async {
    await Future.delayed(_networkDelay);
    final current = _currentMockUser;
    if (current == null) throw ApiException('Not logged in');
    final updated = current.copyWith(bannerUrl: localImagePath);
    _currentMockUser = updated;
    return updated;
  }

  @override
  Future<List<AppUser>> fetchAllUsers() async {
    await Future.delayed(_networkDelay);
    final users = _accounts.keys.map((email) {
      final isDeveloper = email == 'dev@example.com';
      final isPerformer = _performerEmails.contains(email);
      final isSupport = _supportEmails.contains(email);
      final current = _currentMockUser;
      final isSelf = current != null && current.email.trim().toLowerCase() == email;
      return AppUser(
        id: 'u_${email.hashCode}',
        email: email,
        displayName: isSelf ? current!.displayName : email.split('@').first,
        isDeveloper: isDeveloper,
        isPerformer: isPerformer,
        isSupport: isSupport,
        token: '',
        avatarUrl: isSelf ? current!.avatarUrl : '',
        bio: isSelf ? current!.bio : '',
        profileTheme: isSelf ? current!.profileTheme : 'dark',
      );
    }).toList();
    users.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return users;
  }

  @override
  Future<List<Track>> fetchFavoriteTracksByUser(String userId) async {
    await Future.delayed(_networkDelay);
    // Mock has no real per-user favorites tracking beyond the current
    // session; just show the signed-in user's own liked tracks, if any.
    final current = _currentMockUser;
    if (current == null || current.id != userId) return const [];
    final trackMap = {for (final t in _tracks) t.id: t};
    return _favoriteIds.map((id) => trackMap[id]).whereType<Track>().toList();
  }

  @override
  Future<List<Playlist>> fetchPlaylistsByUser(String userId) async {
    await Future.delayed(_networkDelay);
    final current = _currentMockUser;
    if (current == null || current.id != userId) return const [];
    return List.unmodifiable(_playlists);
  }

  @override
  Future<void> deleteUserAccount(String userId) async {
    await Future.delayed(_networkDelay);
    final current = _currentMockUser;
    if (current == null || (!current.isDeveloper && !current.isSupport)) {
      throw ApiException('Only developer or support accounts can delete accounts');
    }
    final email = _accounts.keys.cast<String?>().firstWhere(
          (e) => 'u_${e.hashCode}' == userId,
          orElse: () => null,
        );
    if (email == null) throw ApiException('Account not found');
    _accounts.remove(email);
    _favoriteUserIds.remove(userId);
    if (current.id == userId) {
      _playlists.clear();
      _favoriteIds.clear();
    }
  }

  @override
  Future<List<String>> fetchFavoriteUserIds() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _favoriteUserIds.toList();
  }

  @override
  Future<void> setFavoriteUser({required String userId, required bool favorite}) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (favorite) {
      _favoriteUserIds.add(userId);
    } else {
      _favoriteUserIds.remove(userId);
    }
  }

  /// Mock only tracks the single signed-in account's favorites, so it
  /// can't see other accounts' choices — approximate with 1/0 based on
  /// whether the current account favorited [userId].
  @override
  Future<int> fetchFavoriteUserCount(String userId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _favoriteUserIds.contains(userId) ? 1 : 0;
  }

  /// Developer-only (strictly). The mock backend has no persistent role
  /// flags to drift out of sync in the first place — [fetchAllUsers] and
  /// [login] already recompute `isDeveloper`/`isPerformer`/`isSupport`
  /// from the email lists above on every call — so there's nothing to
  /// update here. Kept as a real call (with the same permission check as
  /// the real backends) so the Settings button behaves the same way
  /// against every [ApiService] implementation.
  @override
  Future<int> syncAccountRoles() async {
    await Future.delayed(_networkDelay);
    final current = _currentMockUser;
    if (current == null || !current.isDeveloper) {
      throw ApiException('Only developer accounts can sync account roles');
    }
    return 0;
  }

  /// Mock has nowhere real to "publish" a build to — just checks
  /// permissions and pretends, like the rest of this class does for
  /// anything that would otherwise touch real storage.
  @override
  Future<void> publishAppUpdate({
    required String localApkPath,
    required String version,
    required int buildNumber,
    required String notes,
    required bool mandatory,
  }) async {
    await Future.delayed(_networkDelay);
    final current = _currentMockUser;
    if (current == null || !(current.isDeveloper || current.isSupport)) {
      throw ApiException('Only developer or support accounts can publish app updates');
    }
  }

  @override
  Future<AppUser> setLikesPrivacy(String privacy) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (!LikesPrivacy.values.contains(privacy)) {
      throw ApiException('Invalid privacy value: $privacy');
    }
    final current = _currentMockUser;
    if (current == null) throw ApiException('Not logged in');
    final updated = current.copyWith(likesPrivacy: privacy);
    _currentMockUser = updated;
    return updated;
  }

  @override
  Future<bool> canViewUserLibrary(String userId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    // The mock backend only ever exposes the signed-in account's own
    // liked tracks/playlists (see fetchFavoriteTracksByUser and
    // fetchPlaylistsByUser above, which return `const []` for anyone
    // else) so there's nothing else to gate here.
    final current = _currentMockUser;
    if (current == null) return false;
    if (current.id == userId || current.isDeveloper || current.isSupport) return true;
    return true;
  }

  @override
  Future<void> setPassword(String newPassword) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (newPassword.isEmpty) throw ApiException('Password is required');
    final current = _currentMockUser;
    if (current == null) throw ApiException('Not logged in');
    _accounts[current.email.trim().toLowerCase()] = newPassword;
  }

  @override
  Future<void> setUserPassword({required String userId, required String newPassword}) async {
    await Future.delayed(_networkDelay);
    if (newPassword.isEmpty) throw ApiException('Password is required');
    final current = _currentMockUser;
    if (current == null || (!current.isDeveloper && !current.isSupport)) {
      throw ApiException('Only developer or support accounts can change other accounts\' passwords');
    }
    final email = _accounts.keys.cast<String?>().firstWhere(
          (e) => 'u_${e.hashCode}' == userId,
          orElse: () => null,
        );
    if (email == null) throw ApiException('Account not found');
    _accounts[email] = newPassword;
  }

  @override
  Future<AppUser> setBio(String bio) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (bio.length > AppUser.bioMaxLength) {
      throw ApiException('Bio must be ${AppUser.bioMaxLength} characters or fewer');
    }
    final current = _currentMockUser;
    if (current == null) throw ApiException('Not logged in');
    final updated = current.copyWith(bio: bio);
    _currentMockUser = updated;
    return updated;
  }

  @override
  Future<AppUser> setDisplayName(String displayName) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) {
      throw ApiException('Nickname is required');
    }
    if (trimmed.length > AppUser.displayNameMaxLength) {
      throw ApiException('Nickname must be ${AppUser.displayNameMaxLength} characters or fewer');
    }
    final current = _currentMockUser;
    if (current == null) throw ApiException('Not logged in');
    final updated = current.copyWith(displayName: trimmed);
    _currentMockUser = updated;
    return updated;
  }

  static const _validProfileThemeKeys = {
    'dark', 'amoled', 'light', 'peach', 'sky', 'purple', 'ruby', 'emerald',
    'wood', 'clouds', 'rain', 'violet', 'pink', 'bubbles',
  };

  @override
  Future<AppUser> setProfileTheme(String themeKey) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (!_validProfileThemeKeys.contains(themeKey)) {
      throw ApiException('Unknown theme: $themeKey');
    }
    final current = _currentMockUser;
    if (current == null) throw ApiException('Not logged in');
    final updated = current.copyWith(profileTheme: themeKey);
    _currentMockUser = updated;
    return updated;
  }

  @override
  Future<List<String>> fetchFeaturedTags() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return List.unmodifiable(_featuredTags);
  }

  @override
  Future<List<String>> setFeaturedTags(List<String> tags) async {
    await Future.delayed(_networkDelay);
    final current = _currentMockUser;
    if (current == null || (!current.isDeveloper && !current.isSupport)) {
      throw ApiException('Only developer or support accounts can set featured tags');
    }
    final cleaned = List<String>.generate(4, (i) => i < tags.length ? tags[i].trim().toLowerCase() : '');
    for (final tag in cleaned) {
      if (tag.isEmpty) continue;
      if (tag.length > Track.maxHashtagLength) {
        throw ApiException('Tags must be ${Track.maxHashtagLength} characters or fewer');
      }
      if (!Track.isValidHashtag(tag)) {
        throw ApiException('Tags can only contain lowercase English letters and numbers');
      }
    }
    _featuredTags = cleaned;
    return List.unmodifiable(_featuredTags);
  }

  @override
  Future<Map<String, String>> fetchArtistAvatars() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return Map.unmodifiable(_artistAvatars);
  }

  @override
  Future<String> uploadArtistAvatar({required String artist, required String localImagePath}) async {
    await Future.delayed(_networkDelay);
    final current = _currentMockUser;
    if (current == null || (!current.isDeveloper && !current.isSupport)) {
      throw ApiException('Only developer or support accounts can set artist avatars');
    }
    // In production this uploads the bytes to Yandex Object Storage and
    // returns the resulting public URL. Here we just reuse the local
    // file path so the picked image can still be previewed on-device.
    _artistAvatars[artist] = localImagePath;
    return localImagePath;
  }

  final List<AppNotification> _notifications = [];
  int _notificationCounter = 0;

  @override
  Future<List<AppNotification>> fetchNotifications() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return List.unmodifiable(_notifications.reversed);
  }

  @override
  Future<AppNotification> sendNotification({required String title, required String body}) async {
    await Future.delayed(_networkDelay);
    final current = _currentMockUser;
    if (current == null || !current.isDeveloper) {
      throw ApiException('Only developer accounts can send notifications');
    }
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ApiException('Notification title is required');
    }
    final notification = AppNotification(
      id: '${_notificationCounter++}',
      title: trimmedTitle,
      body: body.trim(),
      createdAt: DateTime.now(),
    );
    _notifications.add(notification);
    return notification;
  }

  @override
  Future<void> deleteNotification(String id) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final current = _currentMockUser;
    if (current == null || !current.isDeveloper) {
      throw ApiException('Only developer accounts can delete notifications');
    }
    final removed = _notifications.any((n) => n.id == id);
    if (!removed) throw ApiException('Notification not found');
    _notifications.removeWhere((n) => n.id == id);
  }

  @override
  Future<void> removeArtistAvatar(String artist) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final current = _currentMockUser;
    if (current == null || (!current.isDeveloper && !current.isSupport)) {
      throw ApiException('Only developer or support accounts can remove artist avatars');
    }
    _artistAvatars.remove(artist);
  }

  final List<DirectMessage> _messages = [];
  int _messageCounter = 0;

  @override
  Future<List<ConversationSummary>> fetchConversations() async {
    await Future.delayed(const Duration(milliseconds: 150));
    final current = _currentMockUser;
    if (current == null) throw ApiException('Not logged in');
    final myId = current.id;
    final latestByOther = <String, DirectMessage>{};
    for (final m in _messages) {
      if (m.senderId != myId && m.recipientId != myId) continue;
      final otherId = m.senderId == myId ? m.recipientId : m.senderId;
      final existing = latestByOther[otherId];
      if (existing == null || m.createdAt.isAfter(existing.createdAt)) {
        latestByOther[otherId] = m;
      }
    }
    final summaries = latestByOther.entries
        .map((e) => ConversationSummary(
              otherUserId: e.key,
              lastMessage: e.value.text,
              lastMessageAt: e.value.createdAt,
              lastMessageFromMe: e.value.senderId == myId,
            ))
        .toList();
    summaries.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return summaries;
  }

  @override
  Future<List<DirectMessage>> fetchMessages(String otherUserId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final current = _currentMockUser;
    if (current == null) throw ApiException('Not logged in');
    final myId = current.id;
    final between = _messages
        .where((m) =>
            (m.senderId == myId && m.recipientId == otherUserId) ||
            (m.senderId == otherUserId && m.recipientId == myId))
        .toList();
    between.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return between;
  }

  @override
  Future<DirectMessage> sendMessage({required String recipientId, required String text}) async {
    await Future.delayed(_networkDelay);
    final current = _currentMockUser;
    if (current == null) throw ApiException('Not logged in');
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ApiException('Message text is required');
    if (trimmed.length > DirectMessage.maxLength) throw ApiException('Message is too long');
    if (recipientId == current.id) throw ApiException('Cannot message yourself');
    final message = DirectMessage(
      id: 'm_${_messageCounter++}',
      senderId: current.id,
      recipientId: recipientId,
      text: trimmed,
      createdAt: DateTime.now(),
    );
    _messages.add(message);
    return message;
  }

  final Map<String, Map<String, DateTime>> _readUpTo = {}; // readerId -> otherUserId -> ts

  @override
  Future<void> markThreadRead(String otherUserId) async {
    final current = _currentMockUser;
    if (current == null) throw ApiException('Not logged in');
    (_readUpTo[current.id] ??= {})[otherUserId] = DateTime.now();
  }

  @override
  Future<Map<String, DateTime>> fetchReadReceipts() async {
    final current = _currentMockUser;
    if (current == null) throw ApiException('Not logged in');
    final receipts = <String, DateTime>{};
    _readUpTo.forEach((readerId, otherMap) {
      final readUpTo = otherMap[current.id];
      if (readUpTo != null) receipts[readerId] = readUpTo;
    });
    return receipts;
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
