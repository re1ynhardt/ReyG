class Playlist {
  final String id;
  final String name;
  final String coverUrl;
  final List<String> trackIds;

  const Playlist({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.trackIds,
  });

  Playlist copyWith({String? name, String? coverUrl, List<String>? trackIds}) => Playlist(
        id: id,
        name: name ?? this.name,
        coverUrl: coverUrl ?? this.coverUrl,
        trackIds: trackIds ?? this.trackIds,
      );

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        coverUrl: json['cover_url'] as String? ?? '',
        trackIds: (json['track_ids'] as List?)?.map((e) => e as String).toList() ?? [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cover_url': coverUrl,
        'track_ids': trackIds,
      };
}
