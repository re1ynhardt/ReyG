/// A community post: free text plus optional images and/or music tracks
/// pulled from the app's own catalog (this is an audio player, so "posting
/// music" means attaching already-uploaded [Track]s by id, not uploading
/// new audio files). Hashtags are stored the same way as [Track]'s, and
/// `likeCount`/`hashtags` together are the seed for a future recommendation
/// system: a per-post like collection (see [YandexStorageApiService]'s
/// `db/post_likes.json`) ties accounts to the hashtags/authors they engage
/// with, which is exactly the signal a "posts you might like" ranker would
/// need later, without requiring any schema change now.
class Post {
  /// Max length of a post's text body.
  static const maxTextLength = 10000;
  /// Max number of images a single post can carry.
  static const maxImages = 5;
  /// Max number of tracks a single post can carry.
  static const maxTracks = 5;
  /// Max number of hashtags a single post can have.
  static const maxHashtags = 8;
  /// Max characters allowed per hashtag (not counting the leading '#').
  static const maxHashtagLength = 24;

  /// Same rule as [Track.isValidHashtag]: lowercase English letters/digits
  /// only, kept consistent so a hashtag means the same thing across tracks
  /// and posts (and so a future recommendation system can join on it).
  static final RegExp hashtagPattern = RegExp(r'^[a-z0-9]+$');

  static bool isValidHashtag(String tag) => hashtagPattern.hasMatch(tag);

  final String id;
  final String authorId;
  final String text;
  final List<String> imageUrls;
  /// Ids of attached [Track]s from the app's catalog (up to [maxTracks]),
  /// or empty if this post has no music attached.
  final List<String> trackIds;
  final List<String> hashtags;
  final int likeCount;
  final DateTime createdAt;

  const Post({
    required this.id,
    required this.authorId,
    required this.text,
    this.imageUrls = const [],
    this.trackIds = const [],
    this.hashtags = const [],
    this.likeCount = 0,
    required this.createdAt,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    // 'track_ids' is the current field; posts created before multi-track
    // support only have a single 'track_id', so fall back to that for
    // anything already stored in the bucket.
    final rawTrackIds = json['track_ids'] as List<dynamic>?;
    final legacyTrackId = json['track_id'] as String?;
    final trackIds = rawTrackIds != null
        ? rawTrackIds.map((e) => e as String).toList()
        : (legacyTrackId != null ? [legacyTrackId] : const <String>[]);

    return Post(
      id: json['id'] as String,
      authorId: json['author_id'] as String,
      text: json['text'] as String? ?? '',
      imageUrls: (json['image_urls'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      trackIds: trackIds,
      hashtags: (json['hashtags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (((json['created_at'] as num?) ?? 0) * 1000).round(),
        isUtc: true,
      ).toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'author_id': authorId,
        'text': text,
        'image_urls': imageUrls,
        'track_ids': trackIds,
        'hashtags': hashtags,
        'like_count': likeCount,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch / 1000,
      };
}
