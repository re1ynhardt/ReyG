import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../models/track.dart';
import '../models/playlist.dart';

/// Simple on-device cache used for requirement #7 (recently played) and
/// for persisting the logged-in user / theme / language between launches.
class CacheService {
  CacheService._internal();
  static final CacheService instance = CacheService._internal();

  static const _kRecentlyPlayed = 'recently_played_ids';
  static const _kMaxRecent = 30;

  static const _kSearchHistory = 'search_history_queries';
  static const _kMaxSearchHistory = 15;

  Future<List<String>> getRecentlyPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRecentlyPlayed);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => e as String).toList();
  }

  Future<void> addRecentlyPlayed(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getRecentlyPlayed();
    current.remove(trackId);
    current.insert(0, trackId);
    if (current.length > _kMaxRecent) {
      current.removeRange(_kMaxRecent, current.length);
    }
    await prefs.setString(_kRecentlyPlayed, jsonEncode(current));
  }

  Future<void> clearRecentlyPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRecentlyPlayed);
  }

  /// Search query history. Lives only in on-device SharedPreferences —
  /// never sent to the backend or stored in a database.
  Future<List<String>> getSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSearchHistory);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => e as String).toList();
  }

  Future<void> addSearchHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await getSearchHistory();
    current.removeWhere((q) => q.toLowerCase() == trimmed.toLowerCase());
    current.insert(0, trimmed);
    if (current.length > _kMaxSearchHistory) {
      current.removeRange(_kMaxSearchHistory, current.length);
    }
    await prefs.setString(_kSearchHistory, jsonEncode(current));
  }

  Future<void> removeSearchHistoryItem(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getSearchHistory();
    current.removeWhere((q) => q == query);
    await prefs.setString(_kSearchHistory, jsonEncode(current));
  }

  Future<void> clearSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSearchHistory);
  }

  // --- Messages: last-read timestamps -------------------------------------
  // On-device only: for each conversation (keyed by the other account's
  // id) the epoch-ms timestamp of the last time the current device opened
  // that thread. Used to derive the unread badge on the Messages nav item
  // without needing a server-side "read" flag.
  static const _kMessageLastRead = 'message_last_read';

  Future<Map<String, int>> getMessageLastRead() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kMessageLastRead);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
  }

  Future<void> setMessageLastRead(String otherUserId, int epochMillis) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getMessageLastRead();
    current[otherUserId] = epochMillis;
    await prefs.setString(_kMessageLastRead, jsonEncode(current));
  }

  // --- Messages: recent thread cache ---------------------------------------
  // On-device cache of the most recent messages in each DM thread, keyed by
  // the other account's id. Lets a chat open instantly showing the last
  // known messages while a fresh copy is fetched in the background, instead
  // of blocking on the network every time the thread is opened.
  static const _kMessageThreadCachePrefix = 'message_thread_cache_';
  static const kMaxCachedMessagesPerThread = 100;

  Future<List<DirectMessage>> getCachedMessages(String otherUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_kMessageThreadCachePrefix$otherUserId');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => DirectMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Stores [messages] (oldest first) as the cached copy of this thread,
  /// keeping only the most recent [kMaxCachedMessagesPerThread].
  Future<void> setCachedMessages(String otherUserId, List<DirectMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final toStore = messages.length > kMaxCachedMessagesPerThread
        ? messages.sublist(messages.length - kMaxCachedMessagesPerThread)
        : messages;
    await prefs.setString(
      '$_kMessageThreadCachePrefix$otherUserId',
      jsonEncode(toStore.map((m) => m.toJson()).toList()),
    );
  }

  /// Clears every locally-cached message thread on this device (all keys
  /// under [_kMessageThreadCachePrefix]). Used after a developer wipes
  /// all direct messages bucket-wide, so this device doesn't go on
  /// showing stale cached DMs that no longer exist server-side.
  Future<void> clearAllCachedMessageThreads() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_kMessageThreadCachePrefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  // --- Library: full catalog cache -------------------------------------
  // On-device cache of everything LibraryProvider.loadAll() fetches from
  // the network in one go — the full track catalog, playlists, favorite
  // ids, featured tags, and artist avatars. This is by far the heaviest
  // request in the app (the whole catalog), and it's fired on every cold
  // start, so it gets the same TTL treatment as the Community user list:
  // served from disk with no network call at all while still fresh.
  // (Recently-played ids and search history are on-device-only already —
  // not part of this bundle, and always read fresh regardless of TTL.)
  static const _kLibraryCatalog = 'library_catalog_cache';
  static const _kLibraryCatalogFetchedAt = 'library_catalog_cache_time';
  static const libraryCatalogTtl = Duration(minutes: 15);

  Future<
      ({
        List<Track> tracks,
        List<Playlist> playlists,
        List<String> favoriteIds,
        List<String> featuredTags,
        Map<String, String> artistAvatars,
      })?> getCachedLibraryCatalog() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLibraryCatalog);
    if (raw == null) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return (
      tracks: (map['tracks'] as List).map((e) => Track.fromJson(e as Map<String, dynamic>)).toList(),
      playlists: (map['playlists'] as List).map((e) => Playlist.fromJson(e as Map<String, dynamic>)).toList(),
      favoriteIds: (map['favoriteIds'] as List).cast<String>(),
      featuredTags: (map['featuredTags'] as List).cast<String>(),
      artistAvatars: (map['artistAvatars'] as Map<String, dynamic>).cast<String, String>(),
    );
  }

  /// Whether the cached catalog is still within [libraryCatalogTtl] — i.e.
  /// fresh enough that callers can skip the network entirely.
  Future<bool> isLibraryCatalogCacheFresh() async {
    final prefs = await SharedPreferences.getInstance();
    final fetchedAt = prefs.getInt(_kLibraryCatalogFetchedAt);
    if (fetchedAt == null) return false;
    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(fetchedAt));
    return age < libraryCatalogTtl;
  }

  Future<void> setCachedLibraryCatalog({
    required List<Track> tracks,
    required List<Playlist> playlists,
    required List<String> favoriteIds,
    required List<String> featuredTags,
    required Map<String, String> artistAvatars,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kLibraryCatalog,
      jsonEncode({
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'playlists': playlists.map((p) => p.toJson()).toList(),
        'favoriteIds': favoriteIds,
        'featuredTags': featuredTags,
        'artistAvatars': artistAvatars,
      }),
    );
    await prefs.setInt(_kLibraryCatalogFetchedAt, DateTime.now().millisecondsSinceEpoch);
  }


  // On-device cache of the full Community user list (every registered
  // account's public profile info) plus which of them the signed-in
  // account has favorited. Without this, opening the Community tab
  // re-downloads every account's profile every single time. Cached copy
  // is served as-is — no network call at all — for [communityUsersTtl]
  // after it was fetched; [isCommunityUsersCacheFresh] lets callers decide
  // whether a refetch is even worth doing.
  static const _kCommunityUsers = 'community_users_cache';
  static const _kCommunityFavoriteIds = 'community_favorite_user_ids_cache';
  static const _kCommunityUsersFetchedAt = 'community_users_cache_time';
  static const communityUsersTtl = Duration(minutes: 15);

  Future<({List<AppUser> users, List<String> favoriteUserIds})?> getCachedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCommunityUsers);
    if (raw == null) return null;
    final favRaw = prefs.getString(_kCommunityFavoriteIds);
    return (
      users: (jsonDecode(raw) as List).map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList(),
      favoriteUserIds: favRaw == null ? <String>[] : (jsonDecode(favRaw) as List).cast<String>(),
    );
  }

  /// Whether the cached user list is still within [communityUsersTtl] —
  /// i.e. fresh enough that callers can skip the network entirely.
  Future<bool> isCommunityUsersCacheFresh() async {
    final prefs = await SharedPreferences.getInstance();
    final fetchedAt = prefs.getInt(_kCommunityUsersFetchedAt);
    if (fetchedAt == null) return false;
    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(fetchedAt));
    return age < communityUsersTtl;
  }

  Future<void> setCachedUsers(List<AppUser> users, List<String> favoriteUserIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCommunityUsers, jsonEncode(users.map((u) => u.toJson()).toList()));
    await prefs.setString(_kCommunityFavoriteIds, jsonEncode(favoriteUserIds));
    await prefs.setInt(_kCommunityUsersFetchedAt, DateTime.now().millisecondsSinceEpoch);
  }

  // --- Community: single-profile cache ---------------------------------
  // Caches one account's Community profile payload — their liked tracks,
  // playlists, and fan (favorite-user) count — keyed by user id, so
  // reopening the same profile within [profileTtl] shows instantly with
  // no network calls instead of re-fetching all three every time.
  static const _kProfileCachePrefix = 'community_profile_cache_';
  static const _kProfileCacheFetchedAtPrefix = 'community_profile_cache_time_';
  static const profileTtl = Duration(minutes: 15);

  Future<bool> isProfileCacheFresh(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final fetchedAt = prefs.getInt('$_kProfileCacheFetchedAtPrefix$userId');
    if (fetchedAt == null) return false;
    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(fetchedAt));
    return age < profileTtl;
  }

  Future<({List<Track> tracks, List<Playlist> playlists, int favoriteUserCount})?> getCachedProfile(
    String userId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_kProfileCachePrefix$userId');
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return (
      tracks: (decoded['tracks'] as List).map((e) => Track.fromJson(e as Map<String, dynamic>)).toList(),
      playlists: (decoded['playlists'] as List).map((e) => Playlist.fromJson(e as Map<String, dynamic>)).toList(),
      favoriteUserCount: decoded['favorite_user_count'] as int,
    );
  }

  Future<void> setCachedProfile(
    String userId, {
    required List<Track> tracks,
    required List<Playlist> playlists,
    required int favoriteUserCount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_kProfileCachePrefix$userId',
      jsonEncode({
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'playlists': playlists.map((p) => p.toJson()).toList(),
        'favorite_user_count': favoriteUserCount,
      }),
    );
    await prefs.setInt('$_kProfileCacheFetchedAtPrefix$userId', DateTime.now().millisecondsSinceEpoch);
  }

  /// Drops [userId]'s cached profile bundle — used after their account is
  /// deleted so this device doesn't keep showing stale cached data for an
  /// account that no longer exists.
  Future<void> clearCachedProfile(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kProfileCachePrefix$userId');
    await prefs.remove('$_kProfileCacheFetchedAtPrefix$userId');
  }
}
