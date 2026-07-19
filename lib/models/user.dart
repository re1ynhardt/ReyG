class AppUser {
  final String id;
  final String email;
  final String displayName;
  /// Requirement #11: developer accounts get a badge + the ability to
  /// upload tracks directly from inside the app.
  final bool isDeveloper;
  final String token;
  /// Public URL of the user's custom avatar, uploaded to Yandex Object
  /// Storage from the Settings screen. Empty when the user hasn't set one,
  /// in which case the UI falls back to the display-name initial.
  final String avatarUrl;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.isDeveloper,
    required this.token,
    this.avatarUrl = '',
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['display_name'] as String? ?? json['email'] as String,
        isDeveloper: json['is_developer'] as bool? ?? false,
        token: json['token'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'is_developer': isDeveloper,
        'token': token,
        'avatar_url': avatarUrl,
      };

  AppUser copyWith({String? avatarUrl}) => AppUser(
        id: id,
        email: email,
        displayName: displayName,
        isDeveloper: isDeveloper,
        token: token,
        avatarUrl: avatarUrl ?? this.avatarUrl,
      );
}
