class Track {
  /// Max number of hashtags a single track can have.
  static const maxHashtags = 4;
  /// Max characters allowed per hashtag (not counting the leading '#').
  static const maxHashtagLength = 10;

  /// Hashtags must be lowercase English letters/digits only — no
  /// uppercase, no accented letters, no Cyrillic or other non-Latin
  /// scripts, no punctuation or whitespace. Checked in the "add hashtag"
  /// dialog as the person types (which also auto-lowercases input) and
  /// again by every [Track]-consuming service before it's saved, so a
  /// raw API call (or a modified client) can't sneak a bad tag past the
  /// UI filter.
  static final RegExp hashtagPattern = RegExp(r'^[a-z0-9]+$');

  /// Whether [tag] is a non-empty string of only lowercase English
  /// letters/digits.
  static bool isValidHashtag(String tag) => hashtagPattern.hasMatch(tag);

  final String id;
  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final String audioUrl;
  final Duration duration;
  /// True for tracks that were uploaded locally by a developer account
  /// straight from the app (requirement #11), before the real backend exists.
  final bool uploadedLocally;
  /// Public URL of the lyrics text object in storage, or empty if this
  /// track has no lyrics added yet.
  final String lyricsUrl;
  /// User-supplied hashtags (without the leading '#', e.g. 'спокойная'),
  /// shown under the cover art on the now-playing screen. Any signed-in
  /// user can add one (max 4 per track, 10 chars each); only
  /// admin/developer accounts can remove one.
  final List<String> hashtags;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.audioUrl,
    required this.duration,
    this.uploadedLocally = false,
    this.lyricsUrl = '',
    this.hashtags = const [],
  });

  bool get hasLyrics => lyricsUrl.isNotEmpty;

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String? ?? '',
        coverUrl: json['cover_url'] as String? ?? '',
        audioUrl: json['audio_url'] as String,
        duration: Duration(seconds: (json['duration_seconds'] as num?)?.toInt() ?? 0),
        uploadedLocally: json['uploaded_locally'] as bool? ?? false,
        lyricsUrl: json['lyrics_url'] as String? ?? '',
        hashtags: (json['hashtags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'cover_url': coverUrl,
        'audio_url': audioUrl,
        'duration_seconds': duration.inSeconds,
        'uploaded_locally': uploadedLocally,
        'lyrics_url': lyricsUrl,
        'hashtags': hashtags,
      };

  Track copyWith({String? lyricsUrl, List<String>? hashtags}) => Track(
        id: id,
        title: title,
        artist: artist,
        album: album,
        coverUrl: coverUrl,
        audioUrl: audioUrl,
        duration: duration,
        uploadedLocally: uploadedLocally,
        lyricsUrl: lyricsUrl ?? this.lyricsUrl,
        hashtags: hashtags ?? this.hashtags,
      );
}
