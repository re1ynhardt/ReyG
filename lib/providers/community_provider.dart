import 'package:flutter/foundation.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';

/// Backs the Community tab: the full list of registered users, plus a
/// simple client-side filter by display name for the search field at the
/// top of that screen.
class CommunityProvider extends ChangeNotifier {
  CommunityProvider(this._api);

  final ApiService _api;

  List<AppUser> _users = [];
  Set<String> _favoriteUserIds = {};
  bool _loading = false;
  String _query = '';

  bool get loading => _loading;
  String get query => _query;

  /// IDs of accounts the signed-in user has favorited, so screens can
  /// check `favoriteUserIds.contains(user.id)` to show the right icon
  /// state without re-fetching.
  Set<String> get favoriteUserIds => _favoriteUserIds;

  bool isFavoriteUser(String userId) => _favoriteUserIds.contains(userId);

  /// Looks up a cached user by id — e.g. to resolve a DM conversation's
  /// counterpart into a display name/avatar on the Messages tab. Returns
  /// null if the list hasn't been loaded yet or the id isn't found;
  /// callers should fall back to a generic placeholder in that case.
  AppUser? userById(String id) {
    for (final u in _users) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// Users matching [_query] (case-insensitive, matched anywhere in the
  /// display name), with favorited accounts pinned first — each group
  /// keeps the alphabetical order the backend already returned.
  List<AppUser> get users {
    final term = _query.trim().toLowerCase();
    final filtered = term.isEmpty
        ? _users
        : _users.where((u) => u.displayName.toLowerCase().contains(term)).toList();
    final favorites = filtered.where((u) => _favoriteUserIds.contains(u.id)).toList();
    final rest = filtered.where((u) => !_favoriteUserIds.contains(u.id)).toList();
    return [...favorites, ...rest];
  }

  /// Loads the Community user list. By default, serves the on-device
  /// cache (see [CacheService]) whenever it's still fresh — no network
  /// call at all — so switching to the Community tab repeatedly doesn't
  /// re-download every account's profile each time. Pass
  /// [forceRefresh] (e.g. from pull-to-refresh) to always hit the
  /// network and update the cache regardless of its age.
  Future<void> loadUsers({bool forceRefresh = false}) async {
    final cache = CacheService.instance;
    if (!forceRefresh) {
      final cached = await cache.getCachedUsers();
      if (cached != null) {
        _users = cached.users;
        _favoriteUserIds = cached.favoriteUserIds.toSet();
        notifyListeners();
        if (await cache.isCommunityUsersCacheFresh()) {
          // Cache is still within TTL — trust it, skip the network.
          return;
        }
      }
    }
    _loading = true;
    notifyListeners();
    try {
      final results = await Future.wait([_api.fetchAllUsers(), _api.fetchFavoriteUserIds()]);
      _users = results[0] as List<AppUser>;
      _favoriteUserIds = (results[1] as List<String>).toSet();
      await cache.setCachedUsers(_users, _favoriteUserIds.toList());
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void search(String query) {
    _query = query;
    notifyListeners();
  }

  /// Tracks [userId] has liked, for the Community profile screen. Served
  /// from the on-device cache (see [CacheService]) whenever it's still
  /// fresh — no network call — so reopening the same profile doesn't
  /// redownload it every time. Pass [forceRefresh] to always hit the
  /// network (e.g. pull-to-refresh).
  Future<List<Track>> fetchUserLikedTracks(String userId, {bool forceRefresh = false}) async {
    final bundle = await _profileBundle(userId, forceRefresh: forceRefresh);
    return bundle.tracks;
  }

  /// Playlists owned by [userId], for the Community profile screen. Same
  /// on-device caching as [fetchUserLikedTracks].
  Future<List<Playlist>> fetchUserPlaylists(String userId, {bool forceRefresh = false}) async {
    final bundle = await _profileBundle(userId, forceRefresh: forceRefresh);
    return bundle.playlists;
  }

  /// Number of accounts that have favorited [userId] — their fan count,
  /// shown as the "Favorites" stat on the Community profile screen. Same
  /// on-device caching as [fetchUserLikedTracks].
  Future<int> fetchFavoriteUserCount(String userId, {bool forceRefresh = false}) async {
    final bundle = await _profileBundle(userId, forceRefresh: forceRefresh);
    return bundle.favoriteUserCount;
  }

  /// Backs [fetchUserLikedTracks]/[fetchUserPlaylists]/[fetchFavoriteUserCount]:
  /// all three are always requested together by the Community profile
  /// screen, so they're fetched and cached together too, under one TTL
  /// per profile — reopening the same profile within that window costs
  /// zero network calls instead of three.
  Future<({List<Track> tracks, List<Playlist> playlists, int favoriteUserCount})> _profileBundle(
    String userId, {
    bool forceRefresh = false,
  }) async {
    final cache = CacheService.instance;
    if (!forceRefresh) {
      final cached = await cache.getCachedProfile(userId);
      if (cached != null && await cache.isProfileCacheFresh(userId)) {
        return cached;
      }
    }
    final results = await Future.wait([
      _api.fetchFavoriteTracksByUser(userId),
      _api.fetchPlaylistsByUser(userId),
      _api.fetchFavoriteUserCount(userId),
    ]);
    final bundle = (
      tracks: results[0] as List<Track>,
      playlists: results[1] as List<Playlist>,
      favoriteUserCount: results[2] as int,
    );
    await cache.setCachedProfile(
      userId,
      tracks: bundle.tracks,
      playlists: bundle.playlists,
      favoriteUserCount: bundle.favoriteUserCount,
    );
    return bundle;
  }

  /// Whether the signed-in user is allowed to see [userId]'s liked
  /// tracks and playlists, per that account's privacy setting. The
  /// Community profile screen checks this before showing (or hiding)
  /// the tracks/playlists cards.
  Future<bool> canViewUserLibrary(String userId) => _api.canViewUserLibrary(userId);

  /// Developer-only. Permanently deletes [userId]'s account, its
  /// playlists and its favorites, then drops it from the locally cached
  /// user list so the Community tab reflects the removal immediately.
  Future<void> deleteUserAccount(String userId) async {
    await _api.deleteUserAccount(userId);
    _users = _users.where((u) => u.id != userId).toList();
    _favoriteUserIds.remove(userId);
    notifyListeners();
    await CacheService.instance.setCachedUsers(_users, _favoriteUserIds.toList());
    await CacheService.instance.clearCachedProfile(userId);
  }

  /// Developer-only. Sets [userId]'s password without requiring their
  /// old one — used by the debug sheet on a user's Community profile.
  Future<void> setUserPassword({required String userId, required String newPassword}) {
    return _api.setUserPassword(userId: userId, newPassword: newPassword);
  }

  /// Developer-only (strictly — support accounts can't call this
  /// either). Re-syncs every account's role flags with the app's
  /// current developer/support/performer email lists, then reloads the
  /// locally cached user list so any changed badges show up right away.
  /// Returns the number of accounts whose role actually changed.
  Future<int> syncAccountRoles() async {
    final updated = await _api.syncAccountRoles();
    await loadUsers(forceRefresh: true);
    return updated;
  }

  /// Developer/support-only. Straight passthrough to [ApiService.publishAppUpdate] —
  /// uploads the picked APK and rewrites `app/update.json` so every device's
  /// next "check for updates" (or silent startup check) picks it up.
  Future<void> publishAppUpdate({
    required String localApkPath,
    required String version,
    required int buildNumber,
    required String notes,
    required bool mandatory,
  }) {
    return _api.publishAppUpdate(
      localApkPath: localApkPath,
      version: version,
      buildNumber: buildNumber,
      notes: notes,
      mandatory: mandatory,
    );
  }

  /// Toggles whether [userId] is one of the signed-in user's favorite
  /// accounts. Updates optimistically (so the star/list reorders
  /// instantly) and rolls back if the backend call fails.
  Future<void> toggleFavoriteUser(String userId) async {
    final nowFavorite = !_favoriteUserIds.contains(userId);
    if (nowFavorite) {
      _favoriteUserIds.add(userId);
    } else {
      _favoriteUserIds.remove(userId);
    }
    notifyListeners();
    try {
      await _api.setFavoriteUser(userId: userId, favorite: nowFavorite);
      await CacheService.instance.setCachedUsers(_users, _favoriteUserIds.toList());
    } catch (e) {
      if (nowFavorite) {
        _favoriteUserIds.remove(userId);
      } else {
        _favoriteUserIds.add(userId);
      }
      notifyListeners();
      rethrow;
    }
  }
}
