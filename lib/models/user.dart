class AppUser {
  final String id;
  final String email;
  final String displayName;
  /// Requirement #11: developer accounts get a badge + the ability to
  /// upload tracks directly from inside the app.
  final bool isDeveloper;
  final String token;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.isDeveloper,
    required this.token,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['display_name'] as String? ?? json['email'] as String,
        isDeveloper: json['is_developer'] as bool? ?? false,
        token: json['token'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'is_developer': isDeveloper,
        'token': token,
      };
}
