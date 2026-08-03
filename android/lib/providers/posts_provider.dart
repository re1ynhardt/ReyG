import 'package:flutter/foundation.dart';
import '../models/post.dart';
import '../services/api_service.dart';
import '../services/yandex_storage_api_service.dart';

/// Backs the Posts feed, a single user's posts on their Community
/// profile, and the create-post composer. Yandex Storage-only, same
/// pattern as [MessagesProvider]'s uploadImageAttachment/deleteMessage:
/// posts don't exist on the abstract [ApiService], so every method here
/// casts to [YandexStorageApiService] and throws a clear error on any
/// other backend instead of silently doing nothing.
class PostsProvider extends ChangeNotifier {
  PostsProvider(this._api);

  final ApiService _api;

  List<Post> _feed = [];
  Set<String> _likedPostIds = {};
  bool _loading = false;
  String? _hashtagFilter;

  List<Post> get feed => _feed;
  bool get loading => _loading;
  String? get hashtagFilter => _hashtagFilter;
  bool isLiked(String postId) => _likedPostIds.contains(postId);

  YandexStorageApiService _requireYandex() {
    final api = _api;
    if (api is! YandexStorageApiService) {
      throw StateError('Posts aren\'t supported on this backend');
    }
    return api;
  }

  /// Loads the global feed, or one account's posts when [authorId] is
  /// given (used by the Community profile screen). Pass [hashtag] to
  /// filter the global feed to one tag; ignored together with [authorId].
  Future<void> loadFeed({String? authorId, String? hashtag}) async {
    final api = _requireYandex();
    if (authorId == null) _hashtagFilter = hashtag;
    _loading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.fetchPosts(authorId: authorId, hashtag: authorId == null ? hashtag : null),
        api.fetchLikedPostIds(),
      ]);
      _feed = results[0] as List<Post>;
      _likedPostIds = (results[1] as List<String>).toSet();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Posts by [userId] only — used by the Community profile screen,
  /// doesn't touch the shared feed/filter state above.
  Future<List<Post>> fetchPostsByUser(String userId) async {
    final api = _requireYandex();
    return api.fetchPosts(authorId: userId);
  }

  Future<Post> createPost({
    required String text,
    List<String> localImagePaths = const [],
    List<String> trackIds = const [],
    List<String> hashtags = const [],
  }) async {
    final api = _requireYandex();
    final post = await api.createPost(
      text: text,
      localImagePaths: localImagePaths,
      trackIds: trackIds,
      hashtags: hashtags,
    );
    _feed = [post, ..._feed];
    notifyListeners();
    return post;
  }

  /// Removes [postId] from the current feed immediately, restoring it at
  /// its original position if the backend call fails.
  Future<void> deletePost(String postId) async {
    final api = _requireYandex();
    final index = _feed.indexWhere((p) => p.id == postId);
    final removed = index == -1 ? null : _feed[index];
    if (removed != null) {
      _feed = [..._feed.take(index), ..._feed.skip(index + 1)];
      notifyListeners();
    }
    try {
      await api.deletePost(postId);
    } catch (e) {
      if (removed != null) {
        _feed = [..._feed.take(index), removed, ..._feed.skip(index)];
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Toggles a like on [postId]. Optimistic: flips the heart and count
  /// immediately, rolls back if the backend call fails.
  Future<void> toggleLike(String postId) async {
    final api = _requireYandex();
    final nowLiked = !_likedPostIds.contains(postId);
    if (nowLiked) {
      _likedPostIds.add(postId);
    } else {
      _likedPostIds.remove(postId);
    }
    _feed = [
      for (final p in _feed)
        if (p.id == postId)
          Post(
            id: p.id,
            authorId: p.authorId,
            text: p.text,
            imageUrls: p.imageUrls,
            trackIds: p.trackIds,
            hashtags: p.hashtags,
            likeCount: p.likeCount + (nowLiked ? 1 : -1),
            createdAt: p.createdAt,
          )
        else
          p,
    ];
    notifyListeners();
    try {
      await api.setPostLike(postId: postId, liked: nowLiked);
    } catch (e) {
      if (nowLiked) {
        _likedPostIds.remove(postId);
      } else {
        _likedPostIds.add(postId);
      }
      _feed = [
        for (final p in _feed)
          if (p.id == postId)
            Post(
              id: p.id,
              authorId: p.authorId,
              text: p.text,
              imageUrls: p.imageUrls,
              trackIds: p.trackIds,
              hashtags: p.hashtags,
              likeCount: p.likeCount + (nowLiked ? -1 : 1),
              createdAt: p.createdAt,
            )
          else
            p,
      ];
      notifyListeners();
      rethrow;
    }
  }
}
