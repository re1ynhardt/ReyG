import 'package:flutter/foundation.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../models/user.dart';
import '../services/api_service.dart';

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

  Future<void> loadUsers() async {
    _loading = true;
    notifyListeners();
    try {
      final results = await Future.wait([_api.fetchAllUsers(), _api.fetchFavoriteUserIds()]);
      _users = results[0] as List<AppUser>;
      _favoriteUserIds = (results[1] as List<String>).toSet();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void search(String query) {
    _query = query;
    notifyListeners();
  }

  /// Tracks [userId] has liked, for the Community profile screen. Not
  /// cached on the provider — each profile view fetches fresh.
  Future<List<Track>> fetchUserLikedTracks(String userId) => _api.fetchFavoriteTracksByUser(userId);

  /// Playlists owned by [userId], for the Community profile screen.
  Future<List<Playlist>> fetchUserPlaylists(String userId) => _api.fetchPlaylistsByUser(userId);

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
