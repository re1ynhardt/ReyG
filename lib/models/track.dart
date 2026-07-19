class Track {
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
      };

  Track copyWith({String? lyricsUrl}) => Track(
        id: id,
        title: title,
        artist: artist,
        album: album,
        coverUrl: coverUrl,
        audioUrl: audioUrl,
        duration: duration,
        uploadedLocally: uploadedLocally,
        lyricsUrl: lyricsUrl ?? this.lyricsUrl,
      );
}
