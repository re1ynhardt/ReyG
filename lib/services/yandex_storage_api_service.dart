import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/playlist.dart';
import '../models/track.dart';
import '../models/user.dart';
import '../models/app_notification.dart';
import '../models/message.dart';
import '../models/post.dart';
import 'api_service.dart';
import 'e2ee_service.dart';
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
    this.performerEmails = const {},
    this.supportEmails = const {},
  });

  final String accessKeyId;
  final String secretAccessKey;
  final String bucket;
  final String endpointHost;
  final String region;

  /// Emails that get the developer flag (upload rights) at registration.
  final Set<String> developerEmails;

  /// Emails that get the "исполнитель" (performer/artist) role at
  /// registration — same track-management rights as developers (upload
  /// tracks, delete tracks, delete hashtags) without the rest of the
  /// developer-only surface. Set this in lib/main.dart.
  final Set<String> performerEmails;

  /// Emails that get the "поддержка" (support) role at registration —
  /// exactly the same rights as developer accounts (see [developerEmails]).
  /// Set this in lib/main.dart.
  final Set<String> supportEmails;

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
  static const _notificationsKey = 'db/notifications.json';
  static const _artistAvatarsKey = 'db/artist_avatars.json';
  static const _messagesKey = 'db/messages.json';
  static const _messageReadsKey = 'db/message_reads.json';
  // Deliberately NOT part of the E2EE message payload — DM text (and the
  // attachment JSON riding inside it, see message_attachment.dart) is
  // encrypted so only the two participants can read it, which means a
  // developer/support account deleting a user can't decrypt their
  // conversations to discover which chat images belong to them. This
  // small, unencrypted collection just records "this object URL was
  // uploaded by this account as a chat image", so deleteUserAccount can
  // find and remove those files from the bucket without needing to read
  // anyone's messages. It carries no message content, only ownership.
  static const _chatAttachmentsKey = 'db/chat_attachments.json';
  static const _postsKey = 'db/posts.json';
  // Rows are `{user_id, post_id}` — deliberately separate from the post's
  // own denormalized `like_count` (fast to read for the feed) so we can
  // still answer "did I like this" / "which hashtags does this account
  // engage with" without scanning post text. That per-account engagement
  // trail is the foundation a future recommendation system would read
  // from — nothing more is needed here until that ranker exists.
  static const _postLikesKey = 'db/post_likes.json';
  static const _audioPrefix = 'media/audio/';
  static const _coversPrefix = 'media/covers/';
  static const _avatarsPrefix = 'media/avatars/';
  static const _bannersPrefix = 'media/banners/';
  static const _artistAvatarsPrefix = 'media/artist_avatars/';
  static const _lyricsPrefix = 'media/lyrics/';
  static const _chatImagesPrefix = 'media/chat_images/';
  static const _chatVoicePrefix = 'media/chat_voice/';
  static const _chatVideoNotePrefix = 'media/chat_video_note/';
  static const _maxRetries = 8;
  static const _maxAvatarBytes = 5 * 1024 * 1024;
  static const _maxBannerBytes = 10 * 1024 * 1024;
  static const _maxCoverBytes = 5 * 1024 * 1024;
  static const _postImagesPrefix = 'media/post_images/';
  static const _maxPostImageBytes = 5 * 1024 * 1024;
  // Ciphertext is a little larger than the source recording (12-byte
  // nonce + 16-byte GCM tag), but that's negligible next to this cap —
  // generous enough for several minutes of compressed audio.
  static const _maxVoiceBytes = 15 * 1024 * 1024;
  // Round video messages are capped shorter (60s) than voice notes but
  // carry picture data too, so the byte cap is generous accordingly.
  static const _maxVideoNoteBytes = 40 * 1024 * 1024;
  // Any image format is accepted for playlist covers except GIF (avoids
  // animated covers rendering oddly in fixed-size artwork slots).
  static const _rejectedCoverExtensions = {'.gif'};

  String? _sessionToken;

  /// The session token for which we've already confirmed this device's
  /// E2EE public key is present on the account's row (see
  /// [_ensurePublicKeyPublished]). Deliberately keyed by token, not a
  /// plain bool — a bool would stay `true` forever after the first
  /// login and silently skip publishing again when a DIFFERENT account
  /// logs in later on the same running instance (e.g. testing sender +
  /// recipient on one device), leaving the second account's row without
  /// a key.
  String? _publicKeyPublishedForToken;

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

  /// Session-scoped in-memory cache of GETs, keyed by object key — avoids
  /// re-downloading the same `db/*.json` blob (users, tracks, playlists,
  /// messages, ...) on every read within a session, since these only
  /// change when this app itself writes to them. Populated/served only
  /// by [_getObjectCached] (used for plain reads); [_withCollection] and
  /// the other optimistic-write loops below deliberately keep calling
  /// [_getObject] directly for their initial read, since their ETag-based
  /// concurrency check needs the real current state, not a possibly-stale
  /// cached one. Every one of those write paths updates this cache with
  /// the freshly-written bytes/etag right after a successful PUT, so
  /// reads immediately after a write are still cache-consistent.
  final Map<String, ({List<int> bytes, String? etag})?> _objectCache = {};

  Future<({List<int> bytes, String? etag})?> _getObjectCached(String key) async {
    if (_objectCache.containsKey(key)) return _objectCache[key];
    final obj = await _getObject(key);
    _objectCache[key] = obj;
    return obj;
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
  /// [bypassCache] forces a fresh GET instead of serving [_getObjectCached]'s
  /// session-scoped copy — required for collections another account can
  /// write to (messages, read receipts) where a stale in-memory copy would
  /// silently hide their writes for the rest of the session. The fresh
  /// result still repopulates the cache, so other (same-session) readers of
  /// this key benefit from it until the next bypassed read.
  Future<Map<String, dynamic>> _readCollection(String key, {bool bypassCache = false}) async {
    final obj = bypassCache ? await _getObjectFresh(key) : await _getObjectCached(key);
    if (obj == null) return {'items': <dynamic>[]};
    return jsonDecode(utf8.decode(obj.bytes)) as Map<String, dynamic>;
  }

  Future<({List<int> bytes, String? etag})?> _getObjectFresh(String key) async {
    final obj = await _getObject(key);
    _objectCache[key] = obj;
    return obj;
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
        final String newEtag;
        if (obj == null) {
          newEtag = await _putObject(key, body, contentType: 'application/json', createOnly: true);
        } else {
          newEtag = await _putObject(key, body, contentType: 'application/json', ifMatch: obj.etag);
        }
        _objectCache[key] = (bytes: body, etag: newEtag);
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
        'is_performer': config.performerEmails.contains(normalizedEmail),
        'is_support': config.supportEmails.contains(normalizedEmail),
        'token': _randomId(),
        'avatar_url': '',
        'banner_url': '',
        'likes_privacy': LikesPrivacy.all,
        'bio': '',
        'profile_theme': 'dark',
      };
      items.add(row);
      return row;
    });
    _sessionToken = row['token'] as String;
    await _ensurePublicKeyPublished();
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
    await _ensurePublicKeyPublished();
    return _userFromRow(row);
  }

  AppUser _userFromRow(Map<String, dynamic> row) => AppUser(
        id: row['id'] as String,
        email: row['email'] as String,
        displayName: row['display_name'] as String,
        isDeveloper: row['is_developer'] as bool? ?? false,
        isPerformer: row['is_performer'] as bool? ?? false,
        isSupport: row['is_support'] as bool? ?? false,
        token: row['token'] as String,
        avatarUrl: row['avatar_url'] as String? ?? '',
        bannerUrl: row['banner_url'] as String? ?? '',
        likesPrivacy: row['likes_privacy'] as String? ?? LikesPrivacy.all,
        bio: row['bio'] as String? ?? '',
        profileTheme: row['profile_theme'] as String? ?? 'dark',
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
    // Covers reinstalls/new devices: the locally-generated key may not
    // match what's on the account's row yet, or may be missing entirely
    // if this account was created before E2EE existed. Fire-and-forget —
    // restoreSession can't be async, and a failed publish here just
    // means it'll be retried the next time Messages is touched.
    // ignore: discarded_futures
    _ensurePublicKeyPublished().catchError((_) {});
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
    if (user['is_developer'] != true && user['is_performer'] != true && user['is_support'] != true) {
      throw ApiException('Only developer, support, or performer accounts can upload tracks');
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

  /// Developer, support, or performer accounts only. Uploads the lyrics
  /// text to a deterministic per-track key (so editing existing lyrics
  /// overwrites the same object instead of leaving old copies behind)
  /// and records the resulting URL on the track's row.
  @override
  Future<Track> setLyrics({required String trackId, required String lyrics}) async {
    final user = await _currentUserRow();
    if (user['is_developer'] != true && user['is_support'] != true && user['is_performer'] != true) {
      throw ApiException('Only developer, support, or performer accounts can add lyrics');
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
    if (user['is_developer'] != true && user['is_performer'] != true && user['is_support'] != true) {
      throw ApiException('Only developer, support, or performer accounts can remove hashtags');
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

  /// Uploads a custom profile banner for the currently logged-in user.
  /// Same flow as [uploadAvatar]: size-checked locally (up to 10 MB —
  /// banners are wider/heavier than avatars so they get a bigger budget),
  /// uploaded to `media/banners/` (public-read), then the user's row is
  /// updated so the new banner sticks across sessions/devices, with
  /// best-effort cleanup of the old banner file.
  @override
  Future<AppUser> uploadBanner(String localImagePath) async {
    final user = await _currentUserRow();

    final file = File(localImagePath);
    final sizeBytes = await file.length();
    if (sizeBytes > _maxBannerBytes) {
      throw ApiException('Image is too large — max 10 MB');
    }

    final oldBannerUrl = user['banner_url'] as String?;
    final bannerUrl = await _uploadMediaFile(localImagePath, _bannersPrefix);

    final row = await _withCollection(_usersKey, (data) {
      final items = data['items'] as List<dynamic>;
      final match = items.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['id'] == user['id'],
            orElse: () => null,
          );
      if (match == null) throw ApiException('Unauthorized — no account matches this session');
      match['banner_url'] = bannerUrl;
      return match;
    });

    final oldKey = _keyFromPublicUrl(oldBannerUrl);
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
              isPerformer: r['is_performer'] as bool? ?? false,
              isSupport: r['is_support'] as bool? ?? false,
              token: '',
              avatarUrl: r['avatar_url'] as String? ?? '',
              bannerUrl: r['banner_url'] as String? ?? '',
              likesPrivacy: r['likes_privacy'] as String? ?? LikesPrivacy.all,
              bio: r['bio'] as String? ?? '',
              profileTheme: r['profile_theme'] as String? ?? 'dark',
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
    if (viewer['is_support'] == true) return true;
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
    if (caller['is_developer'] != true && caller['is_support'] != true) {
      throw ApiException('Only developer or support accounts can change other accounts\' passwords');
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

  /// Changes the current user's display name (nickname). Shown
  /// throughout the app and on the Community tab/profile.
  @override
  Future<AppUser> setDisplayName(String displayName) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) {
      throw ApiException('Nickname is required');
    }
    if (trimmed.length > AppUser.displayNameMaxLength) {
      throw ApiException('Nickname must be ${AppUser.displayNameMaxLength} characters or fewer');
    }
    final user = await _currentUserRow();
    final row = await _withCollection(_usersKey, (data) {
      final items = data['items'] as List<dynamic>;
      final match = items.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['id'] == user['id'],
            orElse: () => null,
          );
      if (match == null) throw ApiException('Unauthorized — no account matches this session');
      match['display_name'] = trimmed;
      return match;
    });
    return _userFromRow(row);
  }

  /// Keep in sync with [AppThemeOption.values]' storage keys
  /// (lib/theme/app_theme.dart) — duplicated here rather than importing
  /// that file so this service layer stays UI-independent.
  static const _validProfileThemeKeys = {
    'dark', 'amoled', 'light', 'peach', 'sky', 'purple', 'ruby', 'emerald',
    'wood', 'clouds', 'rain', 'violet', 'pink', 'bubbles',
  };

  /// Sets the current user's public profile accent theme (see
  /// [ApiService.setProfileTheme]).
  @override
  Future<AppUser> setProfileTheme(String themeKey) async {
    if (!_validProfileThemeKeys.contains(themeKey)) {
      throw ApiException('Unknown theme: $themeKey');
    }
    final user = await _currentUserRow();
    final row = await _withCollection(_usersKey, (data) {
      final items = data['items'] as List<dynamic>;
      final match = items.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['id'] == user['id'],
            orElse: () => null,
          );
      if (match == null) throw ApiException('Unauthorized — no account matches this session');
      match['profile_theme'] = themeKey;
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

  /// Developer-only. Wipes [userId] out of the bucket as completely as
  /// the data model allows: the account row itself, every playlist it
  /// owns (+ their cover objects), every favorites/favorite-user entry
  /// involving it, its avatar and banner objects, every direct message
  /// it sent or received in either direction (+ read receipts), and
  /// every chat image it ever uploaded (tracked via
  /// [_chatAttachmentsKey] specifically so this step doesn't depend on
  /// decrypting anyone's E2EE messages — see that constant's doc
  /// comment). Tracks it may have uploaded to the shared catalog are
  /// left alone — those aren't "this account's data" in the same sense,
  /// other people may have them favorited/in playlists.
  @override
  Future<void> deleteUserAccount(String userId) async {
    final caller = await _currentUserRow();
    if (caller['is_developer'] != true && caller['is_support'] != true) {
      throw ApiException('Only developer or support accounts can delete accounts');
    }

    String? avatarUrl;
    String? bannerUrl;
    await _withCollection(_usersKey, (data) {
      final items = data['items'] as List<dynamic>;
      final idx = items.indexWhere((r) => (r as Map)['id'] == userId);
      if (idx == -1) throw ApiException('Account not found');
      avatarUrl = (items[idx] as Map)['avatar_url'] as String?;
      bannerUrl = (items[idx] as Map)['banner_url'] as String?;
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

    // Every DM this account sent or received, in either direction —
    // deleting the account row alone would otherwise leave the other
    // party's conversation with a message thread from a ghost id.
    await _withCollection(_messagesKey, (data) {
      final items = data['items'] as List<dynamic>;
      items.removeWhere(
          (r) => (r as Map)['sender_id'] == userId || r['recipient_id'] == userId);
      return null;
    });

    // Read receipts this account owns, and other accounts' receipts
    // that reference it as the other party.
    await _withCollection(_messageReadsKey, (data) {
      final items = data['items'] as List<dynamic>;
      items.removeWhere(
          (r) => (r as Map)['reader_id'] == userId || r['other_user_id'] == userId);
      return null;
    });

    // Every chat image this account uploaded — see _chatAttachmentsKey's
    // doc comment for why this can't just be read out of the (E2EE)
    // message rows above.
    final chatImageUrls = <String?>[];
    await _withCollection(_chatAttachmentsKey, (data) {
      final items = data['items'] as List<dynamic>;
      final owned = items.where((r) => (r as Map)['uploader_id'] == userId);
      for (final r in owned) {
        chatImageUrls.add((r as Map)['url'] as String?);
      }
      items.removeWhere((r) => (r as Map)['uploader_id'] == userId);
      return null;
    });

    // Every post this account authored, plus its images, and every like
    // row it left on (or received on) any post.
    final postImageUrls = <String?>[];
    await _withCollection(_postsKey, (data) {
      final items = data['items'] as List<dynamic>;
      final owned = items.where((r) => (r as Map)['author_id'] == userId);
      for (final r in owned) {
        postImageUrls.addAll(((r as Map)['image_urls'] as List<dynamic>? ?? const []).cast<String?>());
      }
      final ownedIds = owned.map((r) => (r as Map)['id'] as String).toSet();
      items.removeWhere((r) => ownedIds.contains((r as Map)['id']));
      return null;
    });
    await _withCollection(_postLikesKey, (data) {
      final items = data['items'] as List<dynamic>;
      items.removeWhere((r) => (r as Map)['user_id'] == userId);
      return null;
    });

    // Best-effort cleanup of files — the account/playlist/message
    // metadata is already gone either way, so a failure here shouldn't
    // surface as an error to the UI.
    for (final url in [avatarUrl, bannerUrl, ...coverUrls, ...chatImageUrls, ...postImageUrls]) {
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

  /// Number of accounts that have added [userId] to their favorites —
  /// counts rows in [_favoriteUsersKey] on the *other* side of the
  /// `{user_id, favorite_user_id}` pair from [fetchFavoriteUserIds].
  @override
  Future<int> fetchFavoriteUserCount(String userId) async {
    final data = await _readCollection(_favoriteUsersKey);
    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    return items.where((r) => r['favorite_user_id'] == userId).length;
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

  /// Developer-only (strictly — support accounts are rejected too, see
  /// [ApiService.syncAccountRoles]). Walks every account row and
  /// recomputes its `is_developer`/`is_performer`/`is_support` flags from
  /// [config]'s email lists, overwriting whatever was stored at
  /// registration time. This is how an account that was registered
  /// before an email was added to (or removed from) one of those lists
  /// picks up the change, without deleting and re-registering it.
  @override
  Future<int> syncAccountRoles() async {
    final caller = await _currentUserRow();
    if (caller['is_developer'] != true) {
      throw ApiException('Only developer accounts can sync account roles');
    }
    return _withCollection(_usersKey, (data) {
      final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
      var updated = 0;
      for (final row in items) {
        final email = row['email'] as String? ?? '';
        final shouldBeDeveloper = config.developerEmails.contains(email);
        final shouldBePerformer = config.performerEmails.contains(email);
        final shouldBeSupport = config.supportEmails.contains(email);
        if (row['is_developer'] != shouldBeDeveloper ||
            row['is_performer'] != shouldBePerformer ||
            row['is_support'] != shouldBeSupport) {
          row['is_developer'] = shouldBeDeveloper;
          row['is_performer'] = shouldBePerformer;
          row['is_support'] = shouldBeSupport;
          updated++;
        }
      }
      return updated;
    });
  }

  /// Developer/support-only. Reads [localApkPath] fully into memory and
  /// PUTs it to the fixed `app/latest.apk` key (public-read, so
  /// [UpdateService] can download it with a plain GET), then — only once
  /// that succeeds — overwrites `app/update.json` with the new manifest.
  /// That ordering matters: if it were reversed, a device could read a
  /// manifest pointing at a build number whose APK bytes aren't there yet.
  @override
  Future<void> publishAppUpdate({
    required String localApkPath,
    required String version,
    required int buildNumber,
    required String notes,
    required bool mandatory,
  }) async {
    final user = await _currentUserRow();
    if (user['is_developer'] != true && user['is_support'] != true) {
      throw ApiException('Only developer or support accounts can publish app updates');
    }
    if (version.trim().isEmpty) {
      throw ApiException('Version is required');
    }
    if (buildNumber <= 0) {
      throw ApiException('Build number must be a positive integer');
    }

    const apkKey = 'app/latest.apk';
    const manifestKey = 'app/update.json';

    final bytes = await File(localApkPath).readAsBytes();
    await _putObject(
      apkKey,
      bytes,
      contentType: 'application/vnd.android.package-archive',
      publicRead: true,
    );

    final manifest = {
      'buildNumber': buildNumber,
      'version': version.trim(),
      'apkUrl': 'https://${config.endpointHost}/${config.bucket}/$apkKey',
      'notes': notes,
      'mandatory': mandatory,
    };
    await _putObject(
      manifestKey,
      utf8.encode(jsonEncode(manifest)),
      contentType: 'application/json',
      publicRead: true,
    );
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

  /// Developer/performer-only. Removes the track from the catalog, strips it out of
  /// every playlist and every user's favorites, and best-effort deletes
  /// the underlying audio/cover objects from storage so they don't sit
  /// around forever as orphaned files.
  @override
  Future<void> deleteTrack(String trackId) async {
    final user = await _currentUserRow();
    if (user['is_developer'] != true && user['is_performer'] != true && user['is_support'] != true) {
      throw ApiException('Only developer, support, or performer accounts can delete tracks');
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

  /// Lists every object key under [prefix], transparently paging through
  /// ListObjectsV2's `NextContinuationToken` until `IsTruncated` is
  /// false. Parsed with plain regex rather than an XML package — S3's
  /// ListBucketResult is a shallow, non-nested list of `<Key>` (+
  /// `<NextContinuationToken>`) elements, so a full XML parser would be
  /// pure overhead for what this needs.
  Future<List<String>> _listAllKeys(String prefix) async {
    final keys = <String>[];
    String? continuationToken;
    do {
      final params = <String, String>{
        'list-type': '2',
        'prefix': prefix,
        'max-keys': '1000',
        if (continuationToken != null) 'continuation-token': continuationToken,
      };
      final canonicalQuery = YandexSigV4.buildCanonicalQuery(params);
      final bucketPath = '/${config.bucket}';
      final headers = _signer.signedHeaders(
        method: 'GET',
        canonicalPath: bucketPath,
        body: const [],
        canonicalQueryString: canonicalQuery,
      );
      final uri = Uri.parse('https://${config.endpointHost}$bucketPath?$canonicalQuery');
      final res = await http.get(uri, headers: headers);
      if (res.statusCode >= 400) {
        throw ApiException('Yandex Storage ListObjectsV2 failed (${res.statusCode}): ${res.body}');
      }
      final body = res.body;
      keys.addAll(
        RegExp(r'<Key>(.*?)</Key>', dotAll: true)
            .allMatches(body)
            .map((m) => Uri.decodeComponent(m.group(1)!)),
      );
      final truncated = RegExp(r'<IsTruncated>true</IsTruncated>').hasMatch(body);
      continuationToken = truncated
          ? RegExp(r'<NextContinuationToken>(.*?)</NextContinuationToken>', dotAll: true)
              .firstMatch(body)
              ?.group(1)
          : null;
    } while (continuationToken != null);
    return keys;
  }

  /// Deletes every object under [prefix]. Best-effort per key — one
  /// failure doesn't stop the rest from being attempted. Returns how
  /// many were successfully deleted.
  Future<int> _deleteAllObjectsWithPrefix(String prefix) async {
    final keys = await _listAllKeys(prefix);
    var deleted = 0;
    for (final key in keys) {
      try {
        await _deleteObject(key);
        deleted++;
      } catch (_) {
        // Non-fatal — keep going, the caller cares about "as much as
        // possible got cleaned up", not "all-or-nothing".
      }
    }
    return deleted;
  }

  /// Developer-only. Wipes every direct-message conversation for every
  /// user, bucket-wide: the entire `messages` and `message_reads`
  /// collections (all text — including attachment JSON riding inside
  /// message text, see message_attachment.dart), the
  /// `chat_attachments` ownership manifest, and — critically — every
  /// actual object under `media/chat_images/` and `media/chat_voice/`
  /// in the bucket itself, not just the ones the manifest happens to
  /// know about (that manifest only started being written after
  /// chat-attachment ownership tracking was added, so this sweeps the
  /// real prefixes directly to also catch anything uploaded before that
  /// and guarantee nothing is left behind).
  /// There is no per-conversation or per-user selectivity here — this
  /// is a full reset of every private message on the bucket, for
  /// reclaiming storage. Irreversible.
  Future<int> wipeAllDirectMessages() async {
    final caller = await _currentUserRow();
    if (caller['is_developer'] != true) {
      throw ApiException('Only developer accounts can wipe all messages');
    }

    var messageCount = 0;
    await _withCollection(_messagesKey, (data) {
      final items = data['items'] as List<dynamic>;
      messageCount = items.length;
      items.clear();
      return null;
    });

    await _withCollection(_messageReadsKey, (data) {
      (data['items'] as List<dynamic>).clear();
      return null;
    });

    await _withCollection(_chatAttachmentsKey, (data) {
      (data['items'] as List<dynamic>).clear();
      return null;
    });

    // Sweep the actual prefixes rather than trusting the manifest alone —
    // see the doc comment above.
    await _deleteAllObjectsWithPrefix(_chatImagesPrefix);
    await _deleteAllObjectsWithPrefix(_chatVoicePrefix);
    await _deleteAllObjectsWithPrefix(_chatVideoNotePrefix);

    return messageCount;
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
    final obj = await _getObjectCached(_featuredTagsKey);
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
    if (user['is_developer'] != true && user['is_support'] != true) {
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

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      final obj = await _getObject(_featuredTagsKey);
      final body = utf8.encode(jsonEncode(cleaned));
      try {
        final String newEtag;
        if (obj == null) {
          newEtag = await _putObject(_featuredTagsKey, body, contentType: 'application/json', createOnly: true);
        } else {
          newEtag = await _putObject(_featuredTagsKey, body, contentType: 'application/json', ifMatch: obj.etag);
        }
        _objectCache[_featuredTagsKey] = (bytes: body, etag: newEtag);
        return cleaned;
      } on _ConflictException {
        await Future.delayed(Duration(milliseconds: (50 * (1 << attempt)).clamp(0, 1000)) +
            Duration(milliseconds: _rng.nextInt(50)));
        continue;
      }
    }
    throw ApiException('Too many concurrent updates to featured tags, please try again');
  }

  // --- Notifications ----------------------------------------------------
  AppNotification _notificationFromRow(Map<String, dynamic> row) => AppNotification.fromJson(row);

  @override
  Future<List<AppNotification>> fetchNotifications() async {
    await _currentUserRow();
    final data = await _readCollection(_notificationsKey);
    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    items.sort((a, b) => ((b['created_at'] as num?) ?? 0).compareTo((a['created_at'] as num?) ?? 0));
    return items.map(_notificationFromRow).toList();
  }

  /// Strictly developer-only — unlike most admin actions in this file,
  /// support accounts do NOT get this one (checks `is_developer` alone,
  /// not also `is_support`).
  @override
  Future<AppNotification> sendNotification({required String title, required String body}) async {
    final user = await _currentUserRow();
    if (user['is_developer'] != true) {
      throw ApiException('Only developer accounts can send notifications');
    }
    final trimmedTitle = title.trim();
    final trimmedBody = body.trim();
    if (trimmedTitle.isEmpty) {
      throw ApiException('Notification title is required');
    }

    final row = await _withCollection(_notificationsKey, (data) {
      final items = data['items'] as List<dynamic>;
      final row = {
        'id': _randomId(),
        'title': trimmedTitle,
        'body': trimmedBody,
        'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
      };
      items.add(row);
      return row;
    });
    return _notificationFromRow(row);
  }

  /// Strictly developer-only — same restriction as [sendNotification].
  @override
  Future<void> deleteNotification(String id) async {
    final user = await _currentUserRow();
    if (user['is_developer'] != true) {
      throw ApiException('Only developer accounts can delete notifications');
    }
    await _withCollection(_notificationsKey, (data) {
      final items = data['items'] as List<dynamic>;
      final idx = items.indexWhere((r) => (r as Map)['id'] == id);
      if (idx == -1) throw ApiException('Notification not found');
      items.removeAt(idx);
      return null;
    });
  }

  // --- Artists --------------------------------------------------------
  /// Developer-set circular avatar URLs, keyed by exact artist name.
  /// Stored as a single plain JSON object (not the usual
  /// `{items: [...]}` collection shape) — same as [fetchFeaturedTags].
  @override
  Future<Map<String, String>> fetchArtistAvatars() async {
    await _currentUserRow();
    final obj = await _getObjectCached(_artistAvatarsKey);
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
    if (user['is_developer'] != true && user['is_support'] != true) {
      throw ApiException('Only developer or support accounts can set artist avatars');
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
        final String newEtag;
        if (obj == null) {
          newEtag = await _putObject(_artistAvatarsKey, body, contentType: 'application/json', createOnly: true);
        } else {
          newEtag = await _putObject(_artistAvatarsKey, body, contentType: 'application/json', ifMatch: obj.etag);
        }
        _objectCache[_artistAvatarsKey] = (bytes: body, etag: newEtag);
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
    if (user['is_developer'] != true && user['is_support'] != true) {
      throw ApiException('Only developer or support accounts can remove artist avatars');
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
        final String newEtag;
        if (obj == null) {
          newEtag = await _putObject(_artistAvatarsKey, body, contentType: 'application/json', createOnly: true);
        } else {
          newEtag = await _putObject(_artistAvatarsKey, body, contentType: 'application/json', ifMatch: obj.etag);
        }
        _objectCache[_artistAvatarsKey] = (bytes: body, etag: newEtag);
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

  /// Uploads an image to be sent as a chat attachment and returns its
  /// public URL, using the same size/format rules as playlist covers.
  /// Deliberately NOT part of the [ApiService] interface — sending
  /// images is Yandex Storage-only for now (see
  /// [MessagesProvider.uploadImageAttachment], which type-checks for
  /// this concrete class), so the mock and legacy backends don't need a
  /// stub implementation. The message referencing the returned URL still
  /// goes through the normal E2EE `sendMessage` pipeline unchanged (see
  /// message_attachment.dart) — only the image bytes themselves land in
  /// public object storage, same trust level as track/playlist covers.
  Future<String> uploadChatImage(String localImagePath) async {
    final me = await _currentUserRow();
    final file = File(localImagePath);
    final sizeBytes = await file.length();
    if (sizeBytes > _maxCoverBytes) {
      throw ApiException('Image is too large — max 5 MB');
    }
    final dotIndex = localImagePath.lastIndexOf('.');
    final ext = dotIndex == -1 ? '' : localImagePath.substring(dotIndex).toLowerCase();
    if (_rejectedCoverExtensions.contains(ext)) {
      throw ApiException('GIFs are not supported for chat images');
    }
    final url = await _uploadMediaFile(localImagePath, _chatImagesPrefix);
    await _withCollection(_chatAttachmentsKey, (data) {
      final items = data['items'] as List<dynamic>;
      items.add({
        'url': url,
        'uploader_id': me['id'],
        'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
      });
      return null;
    });
    return url;
  }

  /// Uploads a voice-message recording and returns its public URL.
  /// Unlike [uploadChatImage] (where only the *pointer* to the image is
  /// protected — the image bytes themselves sit in the bucket same as
  /// any playlist cover), the recording is encrypted client-side with
  /// [E2EEService.encryptBytes] using the same per-conversation shared
  /// key as message text, BEFORE it ever leaves the device. What lands
  /// in the (public-read) bucket is opaque AES-256-GCM ciphertext, so
  /// nobody who only has bucket/URL access — a network observer,
  /// whoever administers the storage account, anyone who guesses the
  /// key — can play it back; only [recipientId] and this account can
  /// derive the key that decrypts it (see [downloadChatVoice]).
  /// Deliberately NOT part of [ApiService], for the same reason as
  /// [uploadChatImage] — see [MessagesProvider.uploadVoiceAttachment].
  Future<String> uploadChatVoice(String localAudioPath, {required String recipientId}) async {
    await _ensurePublicKeyPublished();
    final me = await _currentUserRow();
    final myId = me['id'] as String;
    final file = File(localAudioPath);
    final sizeBytes = await file.length();
    if (sizeBytes > _maxVoiceBytes) {
      throw ApiException('Voice message is too long');
    }
    final recipientPublicKey = await _publicKeyOf(recipientId);
    if (recipientPublicKey == null) {
      // Same rule as sendMessage: never let a voice message land
      // unencrypted just because we don't have a key on file yet.
      throw ApiException(
        'This account can\'t receive encrypted messages yet — ask them to open Messages once first.',
      );
    }
    final plainBytes = await file.readAsBytes();
    final cipherBytes = await E2EEService.instance.encryptBytes(
      accountId: myId,
      plainBytes: plainBytes,
      otherPartyPublicKeyBase64: recipientPublicKey,
    );
    final key = '$_chatVoicePrefix${_randomId()}.bin';
    await _putObject(
      key,
      cipherBytes,
      // Opaque ciphertext, not a playable audio file — an accurate
      // content-type here would be misleading (and player apps that
      // auto-preview by content-type would just choke on it anyway).
      contentType: 'application/octet-stream',
      publicRead: true,
    );
    final url = 'https://${config.endpointHost}/${config.bucket}/$key';
    await _withCollection(_chatAttachmentsKey, (data) {
      final items = data['items'] as List<dynamic>;
      items.add({
        'url': url,
        'uploader_id': myId,
        'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
      });
      return null;
    });
    return url;
  }

  /// Downloads and decrypts a voice-message attachment previously
  /// uploaded via [uploadChatVoice], returning the raw decrypted audio
  /// bytes ready to write to a local temp file and hand to a player.
  /// [otherUserId] is whoever the OTHER side of that conversation is
  /// (regardless of whether this account sent or received the
  /// recording — ECDH is symmetric, see [E2EEService]).
  Future<Uint8List> downloadChatVoice(String url, {required String otherUserId}) async {
    final me = await _currentUserRow();
    final myId = me['id'] as String;
    final otherPublicKey = await _publicKeyOf(otherUserId);
    if (otherPublicKey == null) {
      throw ApiException('Cannot decrypt this voice message on this device');
    }
    final res = await http.get(Uri.parse(url));
    if (res.statusCode >= 400) {
      throw ApiException('Failed to download voice message (${res.statusCode})');
    }
    return E2EEService.instance.decryptBytes(
      accountId: myId,
      cipherBytes: res.bodyBytes,
      otherPartyPublicKeyBase64: otherPublicKey,
    );
  }

  /// Uploads a round video message ("кружок") recording and returns its
  /// public URL. Identical scheme to [uploadChatVoice] — encrypted
  /// client-side with [E2EEService.encryptBytes] using the same
  /// per-conversation shared key as message text and voice notes,
  /// BEFORE it ever leaves the device, so the (public-read) bucket only
  /// ever holds opaque AES-256-GCM ciphertext. Deliberately NOT part of
  /// [ApiService], for the same reason as [uploadChatVoice] — see
  /// [MessagesProvider.uploadVideoNoteAttachment].
  Future<String> uploadChatVideoNote(String localVideoPath, {required String recipientId}) async {
    await _ensurePublicKeyPublished();
    final me = await _currentUserRow();
    final myId = me['id'] as String;
    final file = File(localVideoPath);
    final sizeBytes = await file.length();
    if (sizeBytes > _maxVideoNoteBytes) {
      throw ApiException('Video message is too long');
    }
    final recipientPublicKey = await _publicKeyOf(recipientId);
    if (recipientPublicKey == null) {
      // Same rule as sendMessage/uploadChatVoice: never let a video
      // message land unencrypted just because we don't have a key on
      // file yet.
      throw ApiException(
        'This account can\'t receive encrypted messages yet — ask them to open Messages once first.',
      );
    }
    final plainBytes = await file.readAsBytes();
    final cipherBytes = await E2EEService.instance.encryptBytes(
      accountId: myId,
      plainBytes: plainBytes,
      otherPartyPublicKeyBase64: recipientPublicKey,
    );
    final key = '$_chatVideoNotePrefix${_randomId()}.bin';
    await _putObject(
      key,
      cipherBytes,
      // Opaque ciphertext, not a playable video file — same reasoning
      // as uploadChatVoice's contentType.
      contentType: 'application/octet-stream',
      publicRead: true,
    );
    final url = 'https://${config.endpointHost}/${config.bucket}/$key';
    await _withCollection(_chatAttachmentsKey, (data) {
      final items = data['items'] as List<dynamic>;
      items.add({
        'url': url,
        'uploader_id': myId,
        'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
      });
      return null;
    });
    return url;
  }

  /// Downloads and decrypts a round video message previously uploaded
  /// via [uploadChatVideoNote], returning the raw decrypted video bytes
  /// ready to write to a local temp file and hand to a player. Same
  /// semantics as [downloadChatVoice].
  Future<Uint8List> downloadChatVideoNote(String url, {required String otherUserId}) async {
    final me = await _currentUserRow();
    final myId = me['id'] as String;
    final otherPublicKey = await _publicKeyOf(otherUserId);
    if (otherPublicKey == null) {
      throw ApiException('Cannot decrypt this video message on this device');
    }
    final res = await http.get(Uri.parse(url));
    if (res.statusCode >= 400) {
      throw ApiException('Failed to download video message (${res.statusCode})');
    }
    return E2EEService.instance.decryptBytes(
      accountId: myId,
      cipherBytes: res.bodyBytes,
      otherPartyPublicKeyBase64: otherPublicKey,
    );
  }

  // --- Messages -----------------------------------------------------------
  // End-to-end encrypted: `row['text']` on the wire and in the bucket is
  // ciphertext (see E2EEService) whenever the sender's device had the
  // recipient's public key at send time. This section is the ONLY place
  // in the app that encrypts/decrypts anything — every other document
  // (tracks, playlists, bios, notifications, ...) stays plain text.

  /// Makes sure this device's E2EE public key is recorded on the
  /// current account's row so other devices can encrypt to it. Cheap to
  /// call repeatedly — only writes when the stored key is missing or
  /// stale, and only actually checks once per app session.
  Future<void> _ensurePublicKeyPublished() async {
    if (_publicKeyPublishedForToken == _sessionToken) return;
    final me = await _currentUserRow();
    final myId = me['id'] as String;
    final myPublicKey = await E2EEService.instance.publicKeyBase64(myId);
    if (me['e2ee_pubkey'] != myPublicKey) {
      await _withCollection(_usersKey, (data) {
        final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
        final row = items.cast<Map<String, dynamic>?>().firstWhere(
              (r) => r?['id'] == myId,
              orElse: () => null,
            );
        row?['e2ee_pubkey'] = myPublicKey;
        return null;
      });
    }
    _publicKeyPublishedForToken = _sessionToken;
  }

  /// Public key for account [userId], or null if that account hasn't
  /// published one yet (e.g. it hasn't opened this build of the app).
  Future<String?> _publicKeyOf(String userId) async {
    final usersData = await _readCollection(_usersKey);
    final items = (usersData['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    final row = items.cast<Map<String, dynamic>?>().firstWhere(
          (r) => r?['id'] == userId,
          orElse: () => null,
        );
    return row?['e2ee_pubkey'] as String?;
  }

  Future<DirectMessage> _decryptRow(
    Map<String, dynamic> row,
    String accountId,
    String otherPartyPublicKey,
  ) async {
    final rawText = row['text'] as String;
    final text = E2EEService.instance.isEncrypted(rawText)
        ? await E2EEService.instance.decrypt(
            accountId: accountId,
            stored: rawText,
            otherPartyPublicKeyBase64: otherPartyPublicKey,
          )
        : rawText;
    return DirectMessage.fromJson({...row, 'text': text});
  }

  @override
  Future<List<ConversationSummary>> fetchConversations() async {
    await _ensurePublicKeyPublished();
    final me = await _currentUserRow();
    final myId = me['id'] as String;
    final data = await _readCollection(_messagesKey, bypassCache: true);
    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    final latestByOther = <String, Map<String, dynamic>>{};
    for (final row in items) {
      final senderId = row['sender_id'] as String;
      final recipientId = row['recipient_id'] as String;
      if (senderId != myId && recipientId != myId) continue;
      final otherId = senderId == myId ? recipientId : senderId;
      final existing = latestByOther[otherId];
      if (existing == null ||
          ((row['created_at'] as num?) ?? 0) > ((existing['created_at'] as num?) ?? 0)) {
        latestByOther[otherId] = row;
      }
    }
    final summaries = <ConversationSummary>[];
    for (final e in latestByOther.entries) {
      final otherPublicKey = await _publicKeyOf(e.key);
      final rawText = e.value['text'] as String;
      final text = (otherPublicKey != null && E2EEService.instance.isEncrypted(rawText))
          ? await E2EEService.instance.decrypt(
              accountId: myId,
              stored: rawText,
              otherPartyPublicKeyBase64: otherPublicKey,
            )
          : rawText;
      summaries.add(ConversationSummary(
        otherUserId: e.key,
        lastMessage: text,
        lastMessageAt: DateTime.fromMillisecondsSinceEpoch(
          (((e.value['created_at'] as num?) ?? 0) * 1000).round(),
          isUtc: true,
        ).toLocal(),
        lastMessageFromMe: e.value['sender_id'] == myId,
      ));
    }
    summaries.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return summaries;
  }

  @override
  Future<List<DirectMessage>> fetchMessages(String otherUserId) async {
    await _ensurePublicKeyPublished();
    final me = await _currentUserRow();
    final myId = me['id'] as String;
    final data = await _readCollection(_messagesKey, bypassCache: true);
    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    final between = items.where((r) =>
        (r['sender_id'] == myId && r['recipient_id'] == otherUserId) ||
        (r['sender_id'] == otherUserId && r['recipient_id'] == myId));
    final otherPublicKey = await _publicKeyOf(otherUserId);
    final messages = <DirectMessage>[];
    for (final row in between) {
      if (otherPublicKey == null) {
        // No key on file for the other side (shouldn't normally happen —
        // it's published the first time they touch Messages) — surface
        // ciphertext rows as-is rather than guessing at a key.
        messages.add(DirectMessage.fromJson(row));
      } else {
        messages.add(await _decryptRow(row, myId, otherPublicKey));
      }
    }
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  @override
  Future<DirectMessage> sendMessage({required String recipientId, required String text}) async {
    await _ensurePublicKeyPublished();
    final me = await _currentUserRow();
    final myId = me['id'] as String;
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ApiException('Message text is required');
    }
    if (trimmed.length > DirectMessage.maxLength) {
      throw ApiException('Message is too long');
    }
    if (recipientId == myId) {
      throw ApiException('Cannot message yourself');
    }
    final usersData = await _readCollection(_usersKey);
    final userItems = (usersData['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    final recipientRow = userItems.cast<Map<String, dynamic>?>().firstWhere(
          (r) => r?['id'] == recipientId,
          orElse: () => null,
        );
    if (recipientRow == null) {
      throw ApiException('Recipient not found');
    }
    final recipientPublicKey = recipientRow['e2ee_pubkey'] as String?;
    if (recipientPublicKey == null) {
      // Never fall back to plain text: without the recipient's key we
      // cannot end-to-end encrypt this message, so refuse to send it
      // instead of silently storing it unencrypted.
      throw ApiException(
        'This account can\'t receive encrypted messages yet — ask them to open Messages once first.',
      );
    }

    final cipherText = await E2EEService.instance.encrypt(
      accountId: myId,
      plainText: trimmed,
      otherPartyPublicKeyBase64: recipientPublicKey,
    );
    final row = await _withCollection(_messagesKey, (data) {
      final items = data['items'] as List<dynamic>;
      final newRow = {
        'id': _randomId(),
        'sender_id': myId,
        'recipient_id': recipientId,
        'text': cipherText,
        'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
      };
      items.add(newRow);
      return newRow;
    });
    return DirectMessage.fromJson({...row, 'text': trimmed});
  }

  /// Yandex Storage-only (same reasoning as [uploadChatImage] /
  /// [wipeAllDirectMessages] above — this doesn't exist on the abstract
  /// [ApiService], so mock/legacy backends are untouched). Edits a
  /// message THIS account sent: re-encrypts [newText] for the recipient
  /// and stamps `edited_at`. Throws [ApiException] if the message isn't
  /// found, isn't yours, or is an attachment (those aren't editable —
  /// see [MessagesProvider]/`ChatScreen` for the guard on the UI side).
  Future<DirectMessage> editMessage({
    required String messageId,
    required String otherUserId,
    required String newText,
  }) async {
    await _ensurePublicKeyPublished();
    final me = await _currentUserRow();
    final myId = me['id'] as String;
    final trimmed = newText.trim();
    if (trimmed.isEmpty) {
      throw ApiException('Message text is required');
    }
    if (trimmed.length > DirectMessage.maxLength) {
      throw ApiException('Message is too long');
    }
    final otherPublicKey = await _publicKeyOf(otherUserId);
    if (otherPublicKey == null) {
      throw ApiException(
        'This account can\'t receive encrypted messages yet — ask them to open Messages once first.',
      );
    }
    final cipherText = await E2EEService.instance.encrypt(
      accountId: myId,
      plainText: trimmed,
      otherPartyPublicKeyBase64: otherPublicKey,
    );
    final editedAt = DateTime.now().millisecondsSinceEpoch / 1000;
    final row = await _withCollection(_messagesKey, (data) {
      final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
      final match = items.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['id'] == messageId && r?['sender_id'] == myId,
            orElse: () => null,
          );
      if (match == null) {
        throw ApiException('Message not found');
      }
      match['text'] = cipherText;
      match['edited_at'] = editedAt;
      return match;
    });
    return DirectMessage.fromJson({...row, 'text': trimmed});
  }

  /// Yandex Storage-only, same restrictions as [editMessage]. Removes a
  /// message THIS account sent, for both sides of the conversation —
  /// there's no "delete for me only" here, mirroring how [editMessage]
  /// also changes what the other side sees.
  Future<void> deleteMessage({required String messageId}) async {
    final me = await _currentUserRow();
    final myId = me['id'] as String;
    await _withCollection(_messagesKey, (data) {
      final items = data['items'] as List<dynamic>;
      final before = items.length;
      items.removeWhere((r) => (r as Map)['id'] == messageId && r['sender_id'] == myId);
      if (items.length == before) {
        throw ApiException('Message not found');
      }
      return null;
    });
  }
  // A single collection of rows {reader_id, other_user_id, read_up_to}:
  // "reader_id has read every message exchanged with other_user_id up
  // through read_up_to". Each account writes only its own row (keyed by
  // reader_id == the current session), so both sides of a conversation
  // can read the other's row without either being able to forge it.

  @override
  Future<void> markThreadRead(String otherUserId) async {
    final me = await _currentUserRow();
    final myId = me['id'] as String;
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    await _withCollection(_messageReadsKey, (data) {
      final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
      final existing = items.cast<Map<String, dynamic>?>().firstWhere(
            (r) => r?['reader_id'] == myId && r?['other_user_id'] == otherUserId,
            orElse: () => null,
          );
      if (existing != null) {
        existing['read_up_to'] = now;
      } else {
        items.add({'reader_id': myId, 'other_user_id': otherUserId, 'read_up_to': now});
      }
      return null;
    });
  }

  @override
  Future<Map<String, DateTime>> fetchReadReceipts() async {
    final me = await _currentUserRow();
    final myId = me['id'] as String;
    final data = await _readCollection(_messageReadsKey, bypassCache: true);
    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    final receipts = <String, DateTime>{};
    for (final row in items) {
      if (row['other_user_id'] != myId) continue;
      final readerId = row['reader_id'] as String;
      final readUpTo = DateTime.fromMillisecondsSinceEpoch(
        (((row['read_up_to'] as num?) ?? 0) * 1000).round(),
        isUtc: true,
      ).toLocal();
      receipts[readerId] = readUpTo;
    }
    return receipts;
  }

  // --- Posts --------------------------------------------------------------
  // Yandex Storage-only, same reasoning as uploadChatImage/editMessage
  // above: these don't exist on the abstract ApiService, so mock/legacy
  // backends are untouched — callers reach these by casting to
  // YandexStorageApiService (see PostsProvider) and handle the "not
  // supported on this backend" case the same way MessagesProvider does.
  //
  // like_count is deliberately NOT stored on the post row itself — it's
  // derived from _postLikesKey every time a post is read, the same way
  // fetchFavoriteUserCount derives a user's fan count from
  // _favoriteUsersKey, so it can never drift out of sync with the
  // like rows themselves (e.g. after deleteUserAccount removes an
  // account's likes). hashtags + who-liked-what together are the seed
  // for a future recommendation system: enough to build "posts with
  // hashtags this account tends to like" without any schema change.

  Post _postFromRow(Map<String, dynamic> row, Map<String, int> likeCounts) => Post.fromJson({
        ...row,
        'like_count': likeCounts[row['id']] ?? 0,
      });

  /// The feed. Pass [hashtag] (without the leading '#') to filter to posts
  /// carrying that tag, or [authorId] to show one account's posts (used by
  /// the Community profile screen) — both of those stay newest-first.
  ///
  /// The plain global feed (no [hashtag]/[authorId]) is instead ranked by
  /// recommendation: it scores every post by how many times its hashtags
  /// appear among the hashtags of posts *this user has already liked*
  /// (via [_postLikesKey]), highest affinity first, newest-first as the
  /// tiebreaker. A user with no like history yet — or a post with no tag
  /// overlap — scores 0, so the feed degrades gracefully to pure recency
  /// exactly like before recommendations existed.
  Future<List<Post>> fetchPosts({String? hashtag, String? authorId}) async {
    final user = await _currentUserRow();
    final results = await Future.wait([_readCollection(_postsKey), _readCollection(_postLikesKey)]);
    final data = results[0] as Map<String, dynamic>;
    final likesData = results[1] as Map<String, dynamic>;
    final likeRows = (likesData['items'] as List<dynamic>).cast<Map<String, dynamic>>();

    final likeCounts = <String, int>{};
    final myLikedPostIds = <String>{};
    for (final row in likeRows) {
      final postId = row['post_id'] as String;
      likeCounts[postId] = (likeCounts[postId] ?? 0) + 1;
      if (row['user_id'] == user['id']) myLikedPostIds.add(postId);
    }

    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    final term = hashtag?.trim().toLowerCase();
    var filtered = items.where((r) {
      if (authorId != null && r['author_id'] != authorId) return false;
      if (term != null && term.isNotEmpty) {
        final tags = ((r['hashtags'] as List<dynamic>?) ?? const []).cast<String>();
        if (!tags.contains(term)) return false;
      }
      return true;
    }).toList();

    if (authorId == null && (term == null || term.isEmpty)) {
      final tagAffinity = <String, int>{};
      for (final row in items) {
        if (!myLikedPostIds.contains(row['id'])) continue;
        for (final tag in ((row['hashtags'] as List<dynamic>?) ?? const []).cast<String>()) {
          tagAffinity[tag] = (tagAffinity[tag] ?? 0) + 1;
        }
      }
      int scoreOf(Map<String, dynamic> r) {
        final tags = ((r['hashtags'] as List<dynamic>?) ?? const []).cast<String>();
        var score = 0;
        for (final tag in tags) {
          score += tagAffinity[tag] ?? 0;
        }
        return score;
      }
      filtered.sort((a, b) {
        final scoreCmp = scoreOf(b).compareTo(scoreOf(a));
        if (scoreCmp != 0) return scoreCmp;
        return ((b['created_at'] as num?) ?? 0).compareTo((a['created_at'] as num?) ?? 0);
      });
    } else {
      filtered.sort((a, b) => ((b['created_at'] as num?) ?? 0).compareTo((a['created_at'] as num?) ?? 0));
    }
    return filtered.map((r) => _postFromRow(r, likeCounts)).toList();
  }

  /// Ids of posts the current user has liked — drives the filled/outline
  /// heart on the feed and profile without a per-post round trip.
  Future<List<String>> fetchLikedPostIds() async {
    final user = await _currentUserRow();
    final data = await _readCollection(_postLikesKey);
    final items = (data['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    return items.where((r) => r['user_id'] == user['id']).map((r) => r['post_id'] as String).toList();
  }

  /// Creates a post. [localImagePaths] are uploaded to
  /// `media/post_images/` (public-read, 5 MB each, same cap as playlist
  /// covers); [trackIds] attach tracks already in the shared catalog —
  /// posting music here never uploads new audio, it just links to tracks
  /// the app already has. At least one of text/images/tracks must be
  /// present. Enforces [Post.maxTextLength], [Post.maxImages],
  /// [Post.maxTracks], [Post.maxHashtags] and [Post.maxHashtagLength]
  /// server-side too, as a safety net behind whatever the composer UI
  /// already checks.
  Future<Post> createPost({
    required String text,
    List<String> localImagePaths = const [],
    List<String> trackIds = const [],
    List<String> hashtags = const [],
  }) async {
    final user = await _currentUserRow();
    final trimmed = text.trim();
    if (trimmed.length > Post.maxTextLength) {
      throw ApiException('Post text must be ${Post.maxTextLength} characters or fewer');
    }
    if (localImagePaths.length > Post.maxImages) {
      throw ApiException('A post can have at most ${Post.maxImages} images');
    }
    if (trackIds.length > Post.maxTracks) {
      throw ApiException('A post can have at most ${Post.maxTracks} tracks');
    }
    if (trimmed.isEmpty && localImagePaths.isEmpty && trackIds.isEmpty) {
      throw ApiException('A post needs text, an image, or a track');
    }
    final tags = <String>[];
    for (final raw in hashtags) {
      final tag = raw.trim().toLowerCase();
      if (tag.isEmpty) continue;
      if (tag.length > Post.maxHashtagLength) {
        throw ApiException('Hashtag must be ${Post.maxHashtagLength} characters or fewer');
      }
      if (!Post.isValidHashtag(tag)) {
        throw ApiException('Hashtags can only contain lowercase English letters and numbers');
      }
      if (!tags.contains(tag)) tags.add(tag);
    }
    if (tags.length > Post.maxHashtags) {
      throw ApiException('A post can have at most ${Post.maxHashtags} hashtags');
    }

    final dedupedTrackIds = <String>[];
    for (final id in trackIds) {
      if (!dedupedTrackIds.contains(id)) dedupedTrackIds.add(id);
    }
    if (dedupedTrackIds.isNotEmpty) {
      final tracksData = await _readCollection(_tracksKey);
      final trackItems = (tracksData['items'] as List<dynamic>).cast<Map<String, dynamic>>();
      for (final id in dedupedTrackIds) {
        if (!trackItems.any((r) => r['id'] == id)) {
          throw ApiException('Track not found');
        }
      }
    }

    for (final path in localImagePaths) {
      final sizeBytes = await File(path).length();
      if (sizeBytes > _maxPostImageBytes) {
        throw ApiException('Image is too large — max 5 MB');
      }
    }
    final imageUrls = <String>[];
    for (final path in localImagePaths) {
      imageUrls.add(await _uploadMediaFile(path, _postImagesPrefix));
    }

    final row = await _withCollection(_postsKey, (data) {
      final items = data['items'] as List<dynamic>;
      final row = {
        'id': _randomId(),
        'author_id': user['id'],
        'text': trimmed,
        'image_urls': imageUrls,
        'track_ids': dedupedTrackIds,
        'hashtags': tags,
        'created_at': DateTime.now().millisecondsSinceEpoch / 1000,
      };
      items.add(row);
      return row;
    });
    return _postFromRow(row, const {});
  }


  /// Author (or developer/support) only. Removes the post, its like rows,
  /// and best-effort deletes its image files from the bucket.
  Future<void> deletePost(String postId) async {
    final user = await _currentUserRow();
    final isModerator = user['is_developer'] == true || user['is_support'] == true;
    final imageUrls = <String?>[];
    await _withCollection(_postsKey, (data) {
      final items = data['items'] as List<dynamic>;
      final idx = items.indexWhere((r) => (r as Map)['id'] == postId);
      if (idx == -1) throw ApiException('Post not found');
      final row = items[idx] as Map<String, dynamic>;
      // Checked (and, on failure, thrown) BEFORE removing — a throw here
      // aborts before _withCollection ever writes, so an unauthorized
      // call leaves the post untouched instead of deleting it first and
      // rejecting after the fact.
      if (row['author_id'] != user['id'] && !isModerator) {
        throw ApiException('Only the author (or a developer/support account) can delete this post');
      }
      imageUrls.addAll((row['image_urls'] as List<dynamic>? ?? const []).cast<String?>());
      items.removeAt(idx);
      return null;
    });
    await _withCollection(_postLikesKey, (data) {
      final items = data['items'] as List<dynamic>;
      items.removeWhere((r) => (r as Map)['post_id'] == postId);
      return null;
    });
    for (final url in imageUrls) {
      final key = _keyFromPublicUrl(url);
      if (key == null) continue;
      try {
        await _deleteObject(key);
      } catch (_) {
        // Non-fatal.
      }
    }
  }

  /// Likes/unlikes a post for the current user. Safe to call repeatedly —
  /// adding an already-present like (or removing an absent one) is a
  /// no-op rather than an error, mirroring [setFavoriteUser].
  Future<void> setPostLike({required String postId, required bool liked}) async {
    final user = await _currentUserRow();
    await _withCollection(_postLikesKey, (data) {
      final items = data['items'] as List<dynamic>;
      final exists = items.any((r) => r['user_id'] == user['id'] && r['post_id'] == postId);
      if (liked && !exists) {
        items.add({'user_id': user['id'], 'post_id': postId});
      } else if (!liked && exists) {
        items.removeWhere((r) => r['user_id'] == user['id'] && r['post_id'] == postId);
      }
      return null;
    });
  }
}

class ApiException implements Exception {
  final String message;

  ApiException(this.message);

  @override
  String toString() => message;
}
