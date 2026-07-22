import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/playlist.dart';
import '../models/track.dart';
import '../models/user.dart';
import 'api_service.dart';
import 'yandex_sigv4.dart';

/// [ApiService] implementation that talks DIRECTLY to Yandex Object
/// Storage — no Flask app, no Python process, no separate server to start.
/// Open the app and it's already able to read/write everything, as long
/// as [YandexStorageConfig] has valid keys.
///
/// This is the client-only counterpart of the earlier `server.py`
/// reference: every "table" (accounts, tracks, playlists, favorites) is a
/// JSON document living in the bucket, read and written with conditional
/// S3 requests (`If-Match` / `If-None-Match`) so two phones editing the
/// same thing at once don't silently clobber each other — the loser just
/// re-reads and retries automatically. See [_withCollection].
///
/// IMPORTANT SECURITY NOTE — read this before shipping to anyone else:
/// Because the app itself holds the Yandex secret key (hardcoded in
/// [YandexStorageConfig] for now), anyone who extracts it from the APK/IPA
/// gets full read/write access to the ENTIRE bucket — every account, every
/// password hash, every track — directly through the S3 API, completely
/// bypassing this app's login screen and the "is_developer" check. That is
/// an inherent limit of "no server at all": there is no place left to
/// enforce access control except the client, and a client-embedded secret
/// is not really a secret. Login/password here only stop *casual* misuse
/// through the app UI, not a determined attacker who pulls the key out of
/// the app package. If you need real access control (e.g. so a user who
/// isn't a developer truly cannot upload tracks, or one user truly cannot
/// read another user's data), you need at least a thin server that holds
/// the Yandex key itself and issues short-lived, scoped access instead of
/// shipping the master key in the app.
class YandexStorageConfig {
  const YandexStorageConfig({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.bucket,
    this.endpointHost = 'storage.yandexcloud.net',
    this.region = 'ru-central1',
    this.developerEmails = const {'dev@example.com'},
  });

  final String accessKeyId;
  final String secretAccessKey;
  final String bucket;
  final String endpointHost;
  final String region;

  /// Emails that get the developer flag (upload rights) at registration.
  final Set<String> developerEmails;

  Uri get baseUri => Uri.https(endpointHost, '');
}

class _ConflictException implements Exception {}

class YandexStorageApiService implements ApiService {
  YandexStorageApiService(this.config)
      : _signer = YandexSigV4(
          accessKeyId: config.accessKeyId,
          secretAccessKey: config.secretAccessKey,
          region: config.region,
          host: config.endpointHost,
        );

  final YandexStorageConfig config;
  final YandexSigV4 _signer;
  final _rng = Random.secure();

  static const _usersKey = 'db/users.json';
  static const _tracksKey = 'db/tracks.json';
  static const _playlistsKey = 'db/playlists.json';
  static const _favoritesKey = 'db/favorites.json';
  static const _favoriteUsersKey = 'db/favorite_users.json';
  static const _featuredTagsKey = 'db/featured_tags.json';
  static const _artistAvatarsKey = 'db/artist_avatars.json';
  static const _audioPrefix = 'media/audio/';
  static const _coversPrefix = 'media/covers/';
  static const _avatarsPrefix = 'media/avatars/';
  static const _artistAvatarsPrefix = 'media/artist_avatars/';
  static const _lyricsPrefix = 'media/lyrics/';
  static const _maxRetries = 8;
  static const _maxAvatarBytes = 5 * 1024 * 1024;
  static const _maxCoverBytes = 5 * 1024 * 1024;
  // Any image format is accepted for playlist covers except GIF (avoids
  // animated covers rendering oddly in fixed-size artwork slots).
  static const _rejectedCoverExtensions = {'.gif'};

  String? _sessionToken;

  // --- Low-level S3 -------------------------------------------------------
  String _objectPath(String key) => '/${config.bucket}/${_encodePathSegments(key)}';

  String _encodePathSegments(String key) =>
      key.split('/').map((s) => Uri.encodeComponent(s)).join('/');

  Uri _uri(String key) => Uri.parse('https://${config.endpointHost}${_objectPath(key)}');

  Future<({List<int> bytes, String? etag})?> _getObject(String key) async {
    final path = _objectPath(key);
    final headers = _signer.signedHeaders(method: 'GET', canonicalPath: path, body: const []);
    final res = await http.get(_uri(key), headers: headers);
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) {
      throw ApiException('Yandex Storage GET failed (${res.statusCode}): ${res.body}');
    }
    final etag = res.headers['etag']?.replaceAll('"', '');
    return (bytes: res.bodyBytes, etag: etag);
  }

  /// Puts an object. If [ifMatch] is set, only succeeds when the object's
  /// current ETag still equals it. If [createOnly] is true, only succeeds
  /// when no object currently exists at this key. Throws
  /// [_ConflictException] on a 412 Precondition Failed.
  Future<String> _putObject(
    String key,
    List<int> body, {
    required String contentType,
    String? ifMatch,
    bool createOnly = false,
    bool publicRead = false,
  }) async {
    final path = _objectPath(key);
    final extra = <String, String>{
      'content-type': contentType,
      if (ifMatch != null) 'if-match': ifMatch,
      if (createOnly) 'if-none-match': '*',
      if (publicRead) 'x-amz-acl': 'public-read',
    };
    final headers = _signer.signedHeaders(
      method: 'PUT',
      canonicalPath: path,
      body: body,
      extraHeaders: extra,
    );
    final res = await http.put(_uri(key), headers: headers, body: body);
    if (res.statusCode == 412) throw _ConflictException();
    if (res.statusCode >= 400) {
      throw ApiException('Yandex Storage PUT failed (${res.statusCode}): ${res.body}');
    }
    return res.headers['etag']?.replaceAll('"', '') ?? '';
  }

  // --- JSON collections with optimistic concurrency ------------------------
  Future<Map<String, dynamic>> _readCollection(String key) async {
    final obj = await _getObject(key);
    if (obj == null) return {'items': <dynamic>[]};
    return jsonDecode(utf8.decode(obj.bytes)) as Map<String, dynamic>;
  }

  /// Read-modify-write a JSON collection. `mutate` receives the current
  /// collection (mutate it in place / return whatever the caller needs).
  /// Automatically retries if another device wrote to the same key first.
  Future<T> _withCollection<T>(
    String key,
    T Function(Map<String, dynamic> data) mutate,
  ) async {
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      final obj = await _getObject(key);
      final data = obj == null
          ? <String, dynamic>{'items': <dynamic>[]}
          : jsonDecode(utf8.decode(obj.bytes)) as Map<String, dynamic>;
      final result = mutate(data);
      final body = utf8.encode(jsonEncode(data));
      try {
        if (obj == null) {
          await _putObject(key, body, contentType: 'application/json', createOnly: true);
        } else {
          await _putObject(key, body, contentType: 'application/json', ifMatch: obj.etag);
        }
        return result;
      } on _ConflictException {
        await Future.delayed(Duration(milliseconds: (50 * (1 << attempt)).clamp(0, 1000)) +
            Duration(milliseconds: _rng.nextInt(50)));
        continue;
      }
    }
    throw ApiException('Too many concurrent updates to $key, please try again');
  }

  String _randomId() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hashPassword(String password) {
    final salt = _randomId();
    final hash = sha256.convert(utf8.encode('$salt:$password')).toString();
    return '$salt:$hash';
  }

  bool _checkPassword(String password, String stored) {
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    final salt = parts[0];
    final expected = parts[1];
    final actual = sha256.convert(utf8.encode('$salt:$password')).toString();
    return actual == expected;
  }

  // --- Auth -----------------------------------------------------------
  @override
  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw ApiException('email and password are required');
    }
    final row = await _withCollection(_usersKey, (data) {
      final items = data['items'] as List<dynamic>;
      if (items.any((r) => r['email'] == normalizedEmail)) {
        throw ApiException('An account with this email already exists');
      }
      final row = {
        'id': _randomId(),
        'email': normalizedEmail,
        'password_hash': _hashPassword(password),
        'display_name': displayName.trim().isEmpty ? normalizedEmail.split('@').first : displayName.trim(),
        'is_developer': config.developerEmails.contains(normalizedEmail),
        'token': _randomId(),
        'avatar_url': '',
        'likes_privacy': LikesPrivacy.all,
        'bio': '',
      };
      items.add(row);
      return row;
    });
    _sessionToken = row['token'] as String;
    return _userFromRow(row);
  }

  @override
  Future<AppUser> login({required String email, required String password}) async {
    final normalizedEmail = email.trim().toLowerCase();
    final row = await _withCollection(_usersKey, (data) {
      final items = data['items'] as List<dynamic>;
      final match = items.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['email'] == normalizedEmail,
            orElse: () => null,
          );
      // Requirement: never let someone in if the account doesn't exist.
      if (match == null || !_checkPassword(password, match['password_hash'] as String)) {
        throw ApiException('Invalid email or password');
      }
      match['token'] = _randomId();
      return match;
    });
    _sessionToken = row['token'] as String;
    return _userFromRow(row);
  }

  AppUser _userFromRow(Map<String, dynamic> row) => AppUser(
        id: row['id'] as String,
        email: row['email'] as String,
        displayName: row['display_name'] as String,
        isDeveloper: row['is_developer'] as bool? ?? false,
        token: row['token'] as String,
        avatarUrl: row['avatar_url'] as String? ?? '',
        likesPrivacy: row['likes_privacy'] as String? ?? LikesPrivacy.all,
        bio: row['bio'] as String? ?? '',
      );

  /// Every call below re-checks that our token still belongs to an account
  /// that currently exists (requirement: a deleted/renamed account can't
  /// stay "logged in" just because it has an old token cached).
  Future<Map<String, dynamic>> _currentUserRow() async {
    final token = _sessionToken;
    if (token == null) throw ApiException('Not logged in');
    final data = await _readCollection(_usersKey);
    final items = data['items'] as List<dynamic>;
    final match = items.cast<Map<String, dynamic>?>().firstWhere(
          (r) => r?['token'] == token,
          orElse: () => null,
        );
    if (match == null) {
      throw ApiException('Unauthorized — no account matches this session');
    }
    return match;
  }

  /// Called once by the app after restoring a persisted session (see
  /// AuthProvider), so subsequent calls know which account is "current"
  /// without asking the user to log in again.
  @override
  void restoreSession(AppUser user) {
    _sessionToken = user.token;
  }

  // --- Tracks -----------------------------------------------------------
  @override
  Future<List<Track>> fetchTracks() async {
    await _currentUserRow();
    final data = await _readCollection(_tracksKey);
    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    items.sort((a, b) => ((b['created_at'] as num?) ?? 0).compareTo((a['created_at'] as num?) ?? 0));
    return items.map(_trackFromRow).toList();
  }

  @override
  Future<List<Track>> searchTracks(String query) async {
    await _currentUserRow();
    final raw = query.trim().toLowerCase();
    // A leading '#' (e.g. "#phonk") searches hashtags only. Otherwise
    // fall back to the regular title/artist/album search — but still
    // include hashtag matches, so a plain "phonk" also surfaces tracks
    // tagged #phonk even if the word appears nowhere else on the track.
    final isHashtagSearch = raw.startsWith('#');
    final term = isHashtagSearch ? raw.substring(1) : raw;
    if (isHashtagSearch && term.isEmpty) return [];
    final data = await _readCollection(_tracksKey);
    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    final filtered = items.where((r) {
      final hashtags = ((r['hashtags'] as List<dynamic>?) ?? const []).cast<String>();
      final hashtagMatch = hashtags.any((tag) => tag.toLowerCase().contains(term));
      if (isHashtagSearch) return hashtagMatch;
      final title = (r['title'] as String).toLowerCase();
      final artist = (r['artist'] as String).toLowerCase();
      final album = (r['album'] as String? ?? '').toLowerCase();
      return title.contains(term) || artist.contains(term) || album.contains(term) || hashtagMatch;
    });
    return filtered.map(_trackFromRow).toList();
  }

  @override
  Future<Track> uploadTrack({
    required String title,
    required String artist,
    required String album,
    required String localAudioPath,
    String? localCoverPath,
  }) async {
    final user = await _currentUserRow();
    if (user['is_developer'] != true) {
      throw ApiException('Only developer accounts can upload tracks');
    }

    final audioUrl = await _uploadMediaFile(localAudioPath, _audioPrefix);
    final coverUrl = localCoverPath != null ? await _uploadMediaFile(localCoverPath, _coversPrefix) : '';

    final row = await _withCollection(_tracksKey, (data) {
      final items = data['items'] as List<dynamic>;
      final row = {
        'id': _randomId(),
        'title': title,
        'artist': artist,
        'album': album,
        'cover_url': coverUrl,
        'audio_url': audioUrl,
        'duration_seconds': 0,
        'uploaded_locally': true,
        'uploader_id': user['id'],
        'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
      };
      items.add(row);
      return row;
    });
    return _trackFromRow(row);
  }

  /// Lyrics are stored as their own public-read text object (mirroring how
  /// audio/cover files are handled) rather than inline in the tracks JSON,
  /// so we don't have to pull every track's lyrics down just to show the
  /// catalog or search results — they're only fetched when the lyrics
  /// panel is actually opened.
  @override
  Future<String?> fetchLyrics(Track track) async {
    if (!track.hasLyrics) return null;
    final res = await http.get(Uri.parse(track.lyricsUrl));
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) {
      throw ApiException('Failed to load lyrics (${res.statusCode})');
    }
    return utf8.decode(res.bodyBytes);
  }

  /// Developer-only. Uploads the lyrics text to a deterministic
  /// per-track key (so editing existing lyrics overwrites the same
  /// object instead of leaving old copies behind) and records the
  /// resulting URL on the track's row.
  @override
  Future<Track> setLyrics({required String trackId, required String lyrics}) async {
    final user = await _currentUserRow();
    if (user['is_developer'] != true) {
      throw ApiException('Only developer accounts can add lyrics');
    }

    final key = '$_lyricsPrefix$trackId.txt';
    await _putObject(
      key,
      utf8.encode(lyrics),
      contentType: 'text/plain; charset=utf-8',
      publicRead: true,
    );
    final lyricsUrl = 'https://${config.endpointHost}/${config.bucket}/$key';

    final row = await _withCollection(_tracksKey, (data) {
      final items = data['items'] as List<dynamic>;
      final idx = items.indexWhere((r) => (r as Map)['id'] == trackId);
      if (idx == -1) throw ApiException('Track not found');
      final row = items[idx] as Map<String, dynamic>;
      row['lyrics_url'] = lyricsUrl;
      return row;
    });
    return _trackFromRow(row);
  }

  /// Any signed-in user can attach a hashtag to a track. Enforces the
  /// per-track cap and per-tag length as a safety net — the UI already
  /// checks both before calling this, but a second backend/app doing raw
  /// HTTP calls (or a modified client) shouldn't be able to bypass them.
  @override
  Future<Track> addHashtag({required String trackId, required String hashtag}) async {
    final tag = hashtag.trim().toLowerCase();
    if (tag.isEmpty) throw ApiException('Hashtag cannot be empty');
    if (tag.length > Track.maxHashtagLength) {
      throw ApiException('Hashtag must be ${Track.maxHashtagLength} characters or fewer');
    }
    if (!Track.isValidHashtag(tag)) {
      throw ApiException('Hashtags can only contain lowercase English letters and numbers');
    }

    final row = await _withCollection(_tracksKey, (data) {
      final items = data['items'] as List<dynamic>;
      final idx = items.indexWhere((r) => (r as Map)['id'] == trackId);
      if (idx == -1) throw ApiException('Track not found');
      final row = items[idx] as Map<String, dynamic>;
      final tags = ((row['hashtags'] as List<dynamic>?) ?? const []).cast<String>();
      if (tags.contains(tag)) throw ApiException('That hashtag is already on this track');
      if (tags.length >= Track.maxHashtags) {
        throw ApiException('A track can have at most ${Track.maxHashtags} hashtags');
      }
      row['hashtags'] = [...tags, tag];
      return row;
    });
    return _trackFromRow(row);
  }

  /// Admin/developer-only. Removes a hashtag from a track.
  @override
  Future<Track> removeHashtag({required String trackId, required String hashtag}) async {
    final user = await _currentUserRow();
    if (user['is_developer'] != true) {
      throw ApiException('Only admin accounts can remove hashtags');
    }
    final tag = hashtag.trim().toLowerCase();

    final row = await _withCollection(_tracksKey, (data) {
      final items = data['items'] as List<dynamic>;
      final idx = items.indexWhere((r) => (r as Map)['id'] == trackId);
      if (idx == -1) throw ApiException('Track not found');
      final row = items[idx] as Map<String, dynamic>;
      final tags = ((row['hashtags'] as List<dynamic>?) ?? const []).cast<String>();
      row['hashtags'] = tags.where((t) => t != tag).toList();
      return row;
    });
    return _trackFromRow(row);
  }

  /// Uploads a custom avatar for the currently logged-in user. Rejects
  /// anything over 5 MB before touching the network, uploads the image to
  /// `media/avatars/` (public-read, so it can be shown without signing
  /// every request), then updates the user's row so the new avatar sticks
  /// across sessions/devices.
  @override
  Future<AppUser> uploadAvatar(String localImagePath) async {
    final user = await _currentUserRow();

    final file = File(localImagePath);
    final sizeBytes = await file.length();
    if (sizeBytes > _maxAvatarBytes) {
      throw ApiException('Image is too large — max 5 MB');
    }

    final oldAvatarUrl = user['avatar_url'] as String?;
    final avatarUrl = await _uploadMediaFile(localImagePath, _avatarsPrefix);

    final row = await _withCollection(_usersKey, (data) {
      final items = data['items'] as List<dynamic>;
      final match = items.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['id'] == user['id'],
            orElse: () => null,
          );
      if (match == null) throw ApiException('Unauthorized — no account matches this session');
      match['avatar_url'] = avatarUrl;
      return match;
    });

    // Best-effort cleanup of the previous avatar so old images don't pile
    // up in the bucket forever. Non-fatal: the new avatar is already saved
    // either way.
    final oldKey = _keyFromPublicUrl(oldAvatarUrl);
    if (oldKey != null) {
      try {
        await _deleteObject(oldKey);
      } catch (_) {
        // Non-fatal.
      }
    }

    return _userFromRow(row);
  }

  // --- Community --------------------------------------------------------
  /// Every registered account, for the Community tab. Tokens are stripped
  /// (set to `''`) on the way out — these rows aren't the caller's own
  /// session, just other accounts' public profile info to list.
  @override
  Future<List<AppUser>> fetchAllUsers() async {
    await _currentUserRow();
    final data = await _readCollection(_usersKey);
    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    final users = items
        .map((r) => AppUser(
              id: r['id'] as String,
              email: r['email'] as String,
              displayName: r['display_name'] as String,
              isDeveloper: r['is_developer'] as bool? ?? false,
              token: '',
              avatarUrl: r['avatar_url'] as String? ?? '',
              likesPrivacy: r['likes_privacy'] as String? ?? LikesPrivacy.all,
              bio: r['bio'] as String? ?? '',
            ))
        .toList();
    users.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return users;
  }

  /// Whether [viewer] (a row from [_usersKey]) may see [userId]'s liked
  /// tracks and playlists, per that account's [LikesPrivacy] setting.
  /// Always true for the account's own row and for developer accounts.
  Future<bool> _checkCanViewLibrary(Map<String, dynamic> viewer, String userId) async {
    if (viewer['id'] == userId) return true;
    if (viewer['is_developer'] == true) return true;
    final usersData = await _readCollection(_usersKey);
    final items = (usersData['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    final owner = items.cast<Map<String, dynamic>?>().firstWhere((r) => r?['id'] == userId, orElse: () => null);
    if (owner == null) return false;
    final privacy = owner['likes_privacy'] as String? ?? LikesPrivacy.all;
    switch (privacy) {
      case LikesPrivacy.none:
        return false;
      case LikesPrivacy.favoritesOnly:
        // "Only favorites" means only accounts THIS profile's owner has
        // favorited may view it — i.e. a row {user_id: userId,
        // favorite_user_id: viewer['id']} in the favorite-accounts table.
        final favData = await _readCollection(_favoriteUsersKey);
        final favItems = (favData['items'] as List<dynamic>).cast<Map<String, dynamic>>();
        return favItems.any((r) => r['user_id'] == userId && r['favorite_user_id'] == viewer['id']);
      case LikesPrivacy.all:
      default:
        return true;
    }
  }

  /// Whether the current session may see [userId]'s liked tracks and
  /// playlists — see [_checkCanViewLibrary].
  @override
  Future<bool> canViewUserLibrary(String userId) async {
    final viewer = await _currentUserRow();
    return _checkCanViewLibrary(viewer, userId);
  }

  /// Changes the current user's password. No old password is required —
  /// the request is already authenticated via the current session token.
  @override
  Future<void> setPassword(String newPassword) async {
    if (newPassword.isEmpty) {
      throw ApiException('Password is required');
    }
    final user = await _currentUserRow();
    await _withCollection(_usersKey, (data) {
      final items = data['items'] as List<dynamic>;
      final match = items.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['id'] == user['id'],
            orElse: () => null,
          );
      if (match == null) throw ApiException('Unauthorized — no account matches this session');
      match['password_hash'] = _hashPassword(newPassword);
      return null;
    });
  }

  /// Developer-only. Sets [userId]'s password without requiring their
  /// old one — same hashing as [setPassword], just targeting another
  /// account's row instead of the caller's own.
  @override
  Future<void> setUserPassword({required String userId, required String newPassword}) async {
    if (newPassword.isEmpty) {
      throw ApiException('Password is required');
    }
    final caller = await _currentUserRow();
    if (caller['is_developer'] != true) {
      throw ApiException('Only developer accounts can change other accounts\' passwords');
    }
    await _withCollection(_usersKey, (data) {
      final items = data['items'] as List<dynamic>;
      final match = items.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['id'] == userId,
            orElse: () => null,
          );
      if (match == null) throw ApiException('Account not found');
      match['password_hash'] = _hashPassword(newPassword);
      return null;
    });
  }

  /// Updates the current user's [LikesPrivacy] setting.
  @override
  Future<AppUser> setLikesPrivacy(String privacy) async {
    if (!LikesPrivacy.values.contains(privacy)) {
      throw ApiException('Invalid privacy value: $privacy');
    }
    final user = await _currentUserRow();
    final row = await _withCollection(_usersKey, (data) {
      final items = data['items'] as List<dynamic>;
      final match = items.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['id'] == user['id'],
            orElse: () => null,
          );
      if (match == null) throw ApiException('Unauthorized — no account matches this session');
      match['likes_privacy'] = privacy;
      return match;
    });
    return _userFromRow(row);
  }

  /// Updates the current user's profile description, shown under their
  /// avatar on their Community profile.
  @override
  Future<AppUser> setBio(String bio) async {
    if (bio.length > AppUser.bioMaxLength) {
      throw ApiException('Bio must be ${AppUser.bioMaxLength} characters or fewer');
    }
    final user = await _currentUserRow();
    final row = await _withCollection(_usersKey, (data) {
      final items = data['items'] as List<dynamic>;
      final match = items.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['id'] == user['id'],
            orElse: () => null,
          );
      if (match == null) throw ApiException('Unauthorized — no account matches this session');
      match['bio'] = bio;
      return match;
    });
    return _userFromRow(row);
  }

  /// Tracks [userId] has liked (favorited), newest-liked first — same
  /// ordering [LibraryProvider] applies to the current account's own
  /// [fetchFavoriteIds] (the backend appends favorites oldest → newest,
  /// so this reverses them on the way out). Used by the Community
  /// profile screen's "Tracks" tile. Returns an empty list (rather than
  /// throwing) when [userId]'s privacy setting hides it from the current
  /// session — callers that need to distinguish "private" from "no
  /// liked tracks" should check [canViewUserLibrary] first.
  @override
  Future<List<Track>> fetchFavoriteTracksByUser(String userId) async {
    final viewer = await _currentUserRow();
    if (!await _checkCanViewLibrary(viewer, userId)) return const [];
    final favData = await _readCollection(_favoritesKey);
    final favItems = (favData['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    final trackIds = favItems.where((r) => r['user_id'] == userId).map((r) => r['track_id'] as String).toList().reversed;

    final tracksData = await _readCollection(_tracksKey);
    final trackItems = (tracksData['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    final trackRowsById = {for (final r in trackItems) r['id'] as String: r};

    final result = <Track>[];
    for (final id in trackIds) {
      final row = trackRowsById[id];
      if (row != null) result.add(_trackFromRow(row));
    }
    return result;
  }

  /// Playlists owned by [userId]. Read-only from the Community profile
  /// screen's point of view — mutating endpoints (add/remove track,
  /// delete, cover) still only accept the caller's own playlists (see
  /// [fetchPlaylists], which checks `owner_id` against the current
  /// session instead of an arbitrary [userId]).
  @override
  Future<List<Playlist>> fetchPlaylistsByUser(String userId) async {
    final viewer = await _currentUserRow();
    if (!await _checkCanViewLibrary(viewer, userId)) return const [];
    final data = await _readCollection(_playlistsKey);
    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    return items.where((r) => r['owner_id'] == userId).map(_playlistFromRow).toList();
  }

  /// Developer-only. Deletes [userId]'s account row, every playlist it
  /// owns (best-effort deleting their cover objects too), every
  /// favorites entry it made, and its avatar file. Tracks it may have
  /// uploaded are left in the shared catalog — this only removes the
  /// account and things that belong solely to it.
  @override
  Future<void> deleteUserAccount(String userId) async {
    final caller = await _currentUserRow();
    if (caller['is_developer'] != true) {
      throw ApiException('Only developer accounts can delete accounts');
    }

    String? avatarUrl;
    await _withCollection(_usersKey, (data) {
      final items = data['items'] as List<dynamic>;
      final idx = items.indexWhere((r) => (r as Map)['id'] == userId);
      if (idx == -1) throw ApiException('Account not found');
      avatarUrl = (items[idx] as Map)['avatar_url'] as String?;
      items.removeAt(idx);
      return null;
    });

    final coverUrls = <String?>[];
    await _withCollection(_playlistsKey, (data) {
      final items = data['items'] as List<dynamic>;
      final owned = items.where((r) => (r as Map)['owner_id'] == userId);
      for (final r in owned) {
        coverUrls.add((r as Map)['cover_url'] as String?);
      }
      items.removeWhere((r) => (r as Map)['owner_id'] == userId);
      return null;
    });

    await _withCollection(_favoritesKey, (data) {
      final items = data['items'] as List<dynamic>;
      items.removeWhere((r) => (r as Map)['user_id'] == userId);
      return null;
    });

    // Drop the deleted account both from its own favorite-accounts list
    // and from everyone else's — a dangling favorite pointing at a
    // now-nonexistent account would otherwise linger forever.
    await _withCollection(_favoriteUsersKey, (data) {
      final items = data['items'] as List<dynamic>;
      items.removeWhere(
          (r) => (r as Map)['user_id'] == userId || r['favorite_user_id'] == userId);
      return null;
    });

    // Best-effort cleanup of files — the account/playlist metadata is
    // already gone either way, so a failure here shouldn't surface as an
    // error to the UI.
    for (final url in [avatarUrl, ...coverUrls]) {
      final key = _keyFromPublicUrl(url);
      if (key == null) continue;
      try {
        await _deleteObject(key);
      } catch (_) {
        // Non-fatal.
      }
    }
  }

  /// IDs of accounts the current user has favorited, for pinning them to
  /// the top of the Community tab. Distinct collection from track
  /// favorites ([fetchFavoriteIds]/[_favoritesKey]) — this one's rows are
  /// `{user_id, favorite_user_id}`.
  @override
  Future<List<String>> fetchFavoriteUserIds() async {
    final user = await _currentUserRow();
    final data = await _readCollection(_favoriteUsersKey);
    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    return items.where((r) => r['user_id'] == user['id']).map((r) => r['favorite_user_id'] as String).toList();
  }

  @override
  Future<void> setFavoriteUser({required String userId, required bool favorite}) async {
    final user = await _currentUserRow();
    await _withCollection(_favoriteUsersKey, (data) {
      final items = data['items'] as List<dynamic>;
      final exists = items.any((r) => r['user_id'] == user['id'] && r['favorite_user_id'] == userId);
      if (favorite && !exists) {
        items.add({'user_id': user['id'], 'favorite_user_id': userId});
      } else if (!favorite && exists) {
        items.removeWhere((r) => r['user_id'] == user['id'] && r['favorite_user_id'] == userId);
      }
      return null;
    });
  }

  Future<String> _uploadMediaFile(String localPath, String prefix) async {
    final bytes = await File(localPath).readAsBytes();
    final ext = localPath.contains('.') ? localPath.substring(localPath.lastIndexOf('.')) : '';
    final key = '$prefix${_randomId()}$ext';
    await _putObject(
      key,
      bytes,
      contentType: _guessContentType(ext),
      publicRead: true,
    );
    return 'https://${config.endpointHost}/${config.bucket}/$key';
  }

  String _guessContentType(String ext) {
    switch (ext.toLowerCase()) {
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
        return 'audio/mp4';
      case '.wav':
        return 'audio/wav';
      case '.aac':
        return 'audio/aac';
      case '.ogg':
        return 'audio/ogg';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  Track _trackFromRow(Map<String, dynamic> row) => Track.fromJson(row);

  /// Developer-only. Removes the track from the catalog, strips it out of
  /// every playlist and every user's favorites, and best-effort deletes
  /// the underlying audio/cover objects from storage so they don't sit
  /// around forever as orphaned files.
  @override
  Future<void> deleteTrack(String trackId) async {
    final user = await _currentUserRow();
    if (user['is_developer'] != true) {
      throw ApiException('Only developer accounts can delete tracks');
    }

    String? audioUrl;
    String? coverUrl;
    await _withCollection(_tracksKey, (data) {
      final items = data['items'] as List<dynamic>;
      final idx = items.indexWhere((r) => (r as Map)['id'] == trackId);
      if (idx == -1) throw ApiException('Track not found');
      final row = items[idx] as Map<String, dynamic>;
      audioUrl = row['audio_url'] as String?;
      coverUrl = row['cover_url'] as String?;
      items.removeAt(idx);
      return null;
    });

    // Pull it out of every playlist that referenced it.
    await _withCollection(_playlistsKey, (data) {
      final items = data['items'] as List<dynamic>;
      for (final p in items) {
        final trackIds = ((p as Map)['track_ids'] as List).cast<String>();
        trackIds.removeWhere((id) => id == trackId);
      }
      return null;
    });

    // Pull it out of every user's favorites too.
    await _withCollection(_favoritesKey, (data) {
      final items = data['items'] as List<dynamic>;
      items.removeWhere((r) => (r as Map)['track_id'] == trackId);
      return null;
    });

    // Best-effort cleanup of the actual files — metadata is already gone
    // either way, so a failure here shouldn't surface as an error to the UI.
    for (final url in [audioUrl, coverUrl]) {
      final key = _keyFromPublicUrl(url);
      if (key == null) continue;
      try {
        await _deleteObject(key);
      } catch (_) {
        // Non-fatal.
      }
    }
  }

  /// Turns a public URL this service generated (see [_uploadMediaFile])
  /// back into an S3 object key, e.g.
  /// "https://storage.yandexcloud.net/my-bucket/media/audio/xyz.mp3"
  /// -> "media/audio/xyz.mp3".
  String? _keyFromPublicUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final marker = '/${config.bucket}/';
    final idx = url.indexOf(marker);
    if (idx == -1) return null;
    return Uri.decodeComponent(url.substring(idx + marker.length));
  }

  Future<void> _deleteObject(String key) async {
    final path = _objectPath(key);
    final headers = _signer.signedHeaders(method: 'DELETE', canonicalPath: path, body: const []);
    final res = await http.delete(_uri(key), headers: headers);
    // S3 returns 204 on success and (per spec) also on "already gone" —
    // only treat genuine failures as errors.
    if (res.statusCode >= 400 && res.statusCode != 404) {
      throw ApiException('Yandex Storage DELETE failed (${res.statusCode}): ${res.body}');
    }
  }

  // --- Playlists --------------------------------------------------------
  @override
  Future<List<Playlist>> fetchPlaylists() async {
    final user = await _currentUserRow();
    final data = await _readCollection(_playlistsKey);
    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    return items.where((r) => r['owner_id'] == user['id']).map(_playlistFromRow).toList();
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    final user = await _currentUserRow();
    final row = await _withCollection(_playlistsKey, (data) {
      final items = data['items'] as List<dynamic>;
      final row = {
        'id': _randomId(),
        'owner_id': user['id'],
        'name': name,
        'cover_url': '',
        'track_ids': <String>[],
      };
      items.add(row);
      return row;
    });
    return _playlistFromRow(row);
  }

  /// Renames a playlist owned by the current user. Trims [newName] and
  /// rejects it if empty, same validation the create-playlist flow
  /// already applies client-side — kept here too as a safety net since
  /// this writes straight to storage.
  @override
  Future<Playlist> renamePlaylist({required String playlistId, required String newName}) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw ApiException('Playlist name cannot be empty');
    final user = await _currentUserRow();
    final row = await _withCollection(_playlistsKey, (data) {
      final row = _findOwnedPlaylist(data, playlistId, user['id'] as String);
      row['name'] = trimmed;
      return row;
    });
    return _playlistFromRow(row);
  }

  Map<String, dynamic> _findOwnedPlaylist(Map<String, dynamic> data, String playlistId, String ownerId) {
    final items = data['items'] as List<dynamic>;
    final row = items.cast<Map<String, dynamic>?>().firstWhere(
          (r) => r?['id'] == playlistId,
          orElse: () => null,
        );
    if (row == null) throw ApiException('Playlist not found');
    if (row['owner_id'] != ownerId) throw ApiException('Not your playlist');
    return row;
  }

  @override
  Future<void> addTrackToPlaylist({required String playlistId, required String trackId}) async {
    final user = await _currentUserRow();
    await _withCollection(_playlistsKey, (data) {
      final row = _findOwnedPlaylist(data, playlistId, user['id'] as String);
      final trackIds = (row['track_ids'] as List).cast<String>();
      if (!trackIds.contains(trackId)) trackIds.add(trackId);
      return null;
    });
  }

  @override
  Future<void> removeTrackFromPlaylist({required String playlistId, required String trackId}) async {
    final user = await _currentUserRow();
    await _withCollection(_playlistsKey, (data) {
      final row = _findOwnedPlaylist(data, playlistId, user['id'] as String);
      final trackIds = (row['track_ids'] as List).cast<String>();
      trackIds.removeWhere((t) => t == trackId);
      return null;
    });
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    final user = await _currentUserRow();
    await _withCollection(_playlistsKey, (data) {
      _findOwnedPlaylist(data, playlistId, user['id'] as String);
      final items = data['items'] as List<dynamic>;
      items.removeWhere((r) => r['id'] == playlistId);
      return null;
    });
  }

  /// Uploads a custom cover for a playlist owned by the current user.
  /// Rejects anything over 5 MB or a GIF before touching the network,
  /// uploads the image to `media/covers/` (public-read, same prefix
  /// track covers use), then updates the playlist's row so the new
  /// cover sticks across sessions/devices.
  @override
  Future<Playlist> uploadPlaylistCover({required String playlistId, required String localImagePath}) async {
    final user = await _currentUserRow();

    final file = File(localImagePath);
    final sizeBytes = await file.length();
    if (sizeBytes > _maxCoverBytes) {
      throw ApiException('Image is too large — max 5 MB');
    }
    final dotIndex = localImagePath.lastIndexOf('.');
    final ext = dotIndex == -1 ? '' : localImagePath.substring(dotIndex).toLowerCase();
    if (_rejectedCoverExtensions.contains(ext)) {
      throw ApiException('GIFs are not supported for playlist covers');
    }

    // Ownership check happens up front so we don't upload a file to
    // storage only to find out the playlist isn't the caller's.
    final data = await _readCollection(_playlistsKey);
    final oldRow = _findOwnedPlaylist(data, playlistId, user['id'] as String);
    final oldCoverUrl = oldRow['cover_url'] as String?;

    final coverUrl = await _uploadMediaFile(localImagePath, _coversPrefix);

    final row = await _withCollection(_playlistsKey, (data) {
      final row = _findOwnedPlaylist(data, playlistId, user['id'] as String);
      row['cover_url'] = coverUrl;
      return row;
    });

    // Best-effort cleanup of the previous cover so old images don't pile
    // up in the bucket forever. Non-fatal: the new cover is already
    // saved either way.
    final oldKey = _keyFromPublicUrl(oldCoverUrl);
    if (oldKey != null) {
      try {
        await _deleteObject(oldKey);
      } catch (_) {
        // Non-fatal.
      }
    }

    return _playlistFromRow(row);
  }

  /// Clears a playlist's custom cover and best-effort deletes the
  /// underlying object from storage, so the UI falls back to the most
  /// recently added track's cover (handled client-side — see
  /// library_screen.dart) instead of a broken/blank image.
  @override
  Future<Playlist> removePlaylistCover({required String playlistId}) async {
    final user = await _currentUserRow();

    final data = await _readCollection(_playlistsKey);
    final oldRow = _findOwnedPlaylist(data, playlistId, user['id'] as String);
    final oldCoverUrl = oldRow['cover_url'] as String?;

    final row = await _withCollection(_playlistsKey, (data) {
      final row = _findOwnedPlaylist(data, playlistId, user['id'] as String);
      row['cover_url'] = '';
      return row;
    });

    final oldKey = _keyFromPublicUrl(oldCoverUrl);
    if (oldKey != null) {
      try {
        await _deleteObject(oldKey);
      } catch (_) {
        // Non-fatal.
      }
    }

    return _playlistFromRow(row);
  }

  Playlist _playlistFromRow(Map<String, dynamic> row) => Playlist.fromJson(row);

  // --- Favorites ----------------------------------------------------------
  @override
  Future<List<String>> fetchFavoriteIds() async {
    final user = await _currentUserRow();
    final data = await _readCollection(_favoritesKey);
    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    return items.where((r) => r['user_id'] == user['id']).map((r) => r['track_id'] as String).toList();
  }

  @override
  Future<void> setFavorite({required String trackId, required bool favorite}) async {
    final user = await _currentUserRow();
    await _withCollection(_favoritesKey, (data) {
      final items = data['items'] as List<dynamic>;
      final exists = items.any((r) => r['user_id'] == user['id'] && r['track_id'] == trackId);
      if (favorite && !exists) {
        items.add({'user_id': user['id'], 'track_id': trackId});
      } else if (!favorite && exists) {
        items.removeWhere((r) => r['user_id'] == user['id'] && r['track_id'] == trackId);
      }
      return null;
    });
  }

  // --- Featured tags (Home screen) ----------------------------------------
  /// Stored as a single plain JSON array of 4 strings (not the usual
  /// `{items: [...]}` shape — there's only ever one "row" here) so
  /// reading it doesn't require decoding a whole collection.
  @override
  Future<List<String>> fetchFeaturedTags() async {
    await _currentUserRow();
    final obj = await _getObject(_featuredTagsKey);
    if (obj == null) return List<String>.filled(4, '');
    final decoded = (jsonDecode(utf8.decode(obj.bytes)) as List<dynamic>).cast<String>();
    final tags = List<String>.generate(4, (i) => i < decoded.length ? decoded[i] : '');
    return tags;
  }

  /// Developer-only. Overwrites the 4 featured-tag slots (`''` clears a
  /// slot) and returns the resulting list. Uses the same optimistic-
  /// concurrency retry loop as [_withCollection], just against a plain
  /// JSON array instead of a `{items: [...]}` collection.
  @override
  Future<List<String>> setFeaturedTags(List<String> tags) async {
    final user = await _currentUserRow();
    if (user['is_developer'] != true) {
      throw ApiException('Only developer accounts can set featured tags');
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

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      final obj = await _getObject(_featuredTagsKey);
      final body = utf8.encode(jsonEncode(cleaned));
      try {
        if (obj == null) {
          await _putObject(_featuredTagsKey, body, contentType: 'application/json', createOnly: true);
        } else {
          await _putObject(_featuredTagsKey, body, contentType: 'application/json', ifMatch: obj.etag);
        }
        return cleaned;
      } on _ConflictException {
        await Future.delayed(Duration(milliseconds: (50 * (1 << attempt)).clamp(0, 1000)) +
            Duration(milliseconds: _rng.nextInt(50)));
        continue;
      }
    }
    throw ApiException('Too many concurrent updates to featured tags, please try again');
  }

  // --- Artists --------------------------------------------------------
  /// Developer-set circular avatar URLs, keyed by exact artist name.
  /// Stored as a single plain JSON object (not the usual
  /// `{items: [...]}` collection shape) — same as [fetchFeaturedTags].
  @override
  Future<Map<String, String>> fetchArtistAvatars() async {
    await _currentUserRow();
    final obj = await _getObject(_artistAvatarsKey);
    if (obj == null) return {};
    final decoded = jsonDecode(utf8.decode(obj.bytes)) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, v as String));
  }

  /// Developer-only. Uploads/overwrites the avatar for [artist]: rejects
  /// anything over 5 MB before touching the network, uploads the image
  /// to `media/artist_avatars/` (public-read, same as the account avatar
  /// and playlist covers), then records the new URL in the artist
  /// avatars object. Uses the same optimistic-concurrency retry loop as
  /// [setFeaturedTags], just against this key instead.
  @override
  Future<String> uploadArtistAvatar({required String artist, required String localImagePath}) async {
    final user = await _currentUserRow();
    if (user['is_developer'] != true) {
      throw ApiException('Only developer accounts can set artist avatars');
    }

    final file = File(localImagePath);
    final sizeBytes = await file.length();
    if (sizeBytes > _maxAvatarBytes) {
      throw ApiException('Image is too large — max 5 MB');
    }

    final avatarUrl = await _uploadMediaFile(localImagePath, _artistAvatarsPrefix);

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      final obj = await _getObject(_artistAvatarsKey);
      final data = obj == null
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(obj.bytes)) as Map<String, dynamic>;
      final oldAvatarUrl = data[artist] as String?;
      data[artist] = avatarUrl;
      final body = utf8.encode(jsonEncode(data));
      try {
        if (obj == null) {
          await _putObject(_artistAvatarsKey, body, contentType: 'application/json', createOnly: true);
        } else {
          await _putObject(_artistAvatarsKey, body, contentType: 'application/json', ifMatch: obj.etag);
        }
        // Best-effort cleanup of the previous avatar so old images don't
        // pile up in the bucket forever. Non-fatal: the new avatar is
        // already saved either way.
        final oldKey = _keyFromPublicUrl(oldAvatarUrl);
        if (oldKey != null) {
          try {
            await _deleteObject(oldKey);
          } catch (_) {
            // Non-fatal.
          }
        }
        return avatarUrl;
      } on _ConflictException {
        await Future.delayed(Duration(milliseconds: (50 * (1 << attempt)).clamp(0, 1000)) +
            Duration(milliseconds: _rng.nextInt(50)));
        continue;
      }
    }
    throw ApiException('Too many concurrent updates to artist avatars, please try again');
  }

  /// Developer-only. Clears [artist]'s custom avatar and best-effort
  /// deletes the underlying object from storage, so the UI falls back
  /// to that artist's most recent track cover again (handled
  /// client-side — see `LibraryProvider.avatarForArtist`).
  @override
  Future<void> removeArtistAvatar(String artist) async {
    final user = await _currentUserRow();
    if (user['is_developer'] != true) {
      throw ApiException('Only developer accounts can remove artist avatars');
    }

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      final obj = await _getObject(_artistAvatarsKey);
      final data = obj == null
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(obj.bytes)) as Map<String, dynamic>;
      final oldAvatarUrl = data[artist] as String?;
      data.remove(artist);
      final body = utf8.encode(jsonEncode(data));
      try {
        if (obj == null) {
          await _putObject(_artistAvatarsKey, body, contentType: 'application/json', createOnly: true);
        } else {
          await _putObject(_artistAvatarsKey, body, contentType: 'application/json', ifMatch: obj.etag);
        }
        final oldKey = _keyFromPublicUrl(oldAvatarUrl);
        if (oldKey != null) {
          try {
            await _deleteObject(oldKey);
          } catch (_) {
            // Non-fatal.
          }
        }
        return;
      } on _ConflictException {
        await Future.delayed(Duration(milliseconds: (50 * (1 << attempt)).clamp(0, 1000)) +
            Duration(milliseconds: _rng.nextInt(50)));
        continue;
      }
    }
    throw ApiException('Too many concurrent updates to artist avatars, please try again');
  }
}

class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => message;
}
