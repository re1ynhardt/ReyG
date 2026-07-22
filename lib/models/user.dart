/// Who is allowed to see a user's liked tracks and playlists on their
/// Community profile. Stored on [AppUser.likesPrivacy] and set from the
/// Settings screen. Developer accounts can always see everyone's liked
/// tracks/playlists regardless of this setting.
abstract class LikesPrivacy {
  /// Anyone signed in can see this user's liked tracks and playlists.
  static const all = 'all';

  /// Only accounts this user has added to their own favorites (see
  /// ApiService.setFavoriteUser) can see their liked tracks/playlists.
  static const favoritesOnly = 'favorites';

  /// Nobody but this user (and developer accounts) can see them.
  static const none = 'none';

  static const values = [all, favoritesOnly, none];
}

class AppUser {
  /// Enforced by Settings' bio editor and by backends that accept
  /// [ApiService.setBio] — anything longer is rejected.
  static const bioMaxLength = 150;

  /// Enforced by Settings' nickname editor and by backends that accept
  /// [ApiService.setDisplayName] — anything longer (or empty, after
  /// trimming) is rejected.
  static const displayNameMaxLength = 30;

  final String id;
  final String email;
  final String displayName;
  /// Requirement #11: developer accounts get a badge + the ability to
  /// upload tracks directly from inside the app.
  final bool isDeveloper;
  /// "Исполнитель" (performer/artist) role: like developers, these
  /// accounts can upload tracks, delete tracks, and delete hashtags —
  /// but don't get the rest of the developer-only surface (featured
  /// tags, artist avatars, lyrics editing, account management). Set at
  /// registration from [YandexStorageConfig.performerEmails] — see
  /// lib/main.dart.
  final bool isPerformer;
  /// "Поддержка" (support) role: exactly the same rights as developer
  /// accounts (see [isDeveloper]) — just a separate role/badge so support
  /// staff can be distinguished from the app's developers. Set at
  /// registration from [YandexStorageConfig.supportEmails] — see
  /// lib/main.dart.
  final bool isSupport;
  final String token;
  /// Public URL of the user's custom avatar, uploaded to Yandex Object
  /// Storage from the Settings screen. Empty when the user hasn't set one,
  /// in which case the UI falls back to the display-name initial.
  final String avatarUrl;
  /// Public URL of the user's profile banner image, shown behind/above
  /// their avatar on the Community profile screen. Empty when the user
  /// hasn't set one, in which case the UI falls back to a plain
  /// background. Upload flow is not implemented yet — this only carries
  /// a URL if the backend already has one set.
  final String bannerUrl;
  /// Who can see this user's liked tracks and playlists — one of the
  /// [LikesPrivacy] values. Defaults to [LikesPrivacy.all].
  final String likesPrivacy;
  /// Short free-text profile description (max [bioMaxLength] characters), set from
  /// Settings and shown under the avatar on this user's Community
  /// profile. Empty when the user hasn't set one, in which case nothing
  /// is shown.
  final String bio;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.isDeveloper,
    this.isPerformer = false,
    this.isSupport = false,
    required this.token,
    this.avatarUrl = '',
    this.bannerUrl = '',
    this.likesPrivacy = LikesPrivacy.all,
    this.bio = '',
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['display_name'] as String? ?? json['email'] as String,
        isDeveloper: json['is_developer'] as bool? ?? false,
        isPerformer: json['is_performer'] as bool? ?? false,
        isSupport: json['is_support'] as bool? ?? false,
        token: json['token'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String? ?? '',
        bannerUrl: json['banner_url'] as String? ?? '',
        likesPrivacy: json['likes_privacy'] as String? ?? LikesPrivacy.all,
        bio: json['bio'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'display_name': displayName,
        'is_developer': isDeveloper,
        'is_performer': isPerformer,
        'is_support': isSupport,
        'token': token,
        'avatar_url': avatarUrl,
        'banner_url': bannerUrl,
        'likes_privacy': likesPrivacy,
        'bio': bio,
      };

  AppUser copyWith({
    String? displayName,
    String? avatarUrl,
    String? bannerUrl,
    String? likesPrivacy,
    String? bio,
  }) =>
      AppUser(
        id: id,
        email: email,
        displayName: displayName ?? this.displayName,
        isDeveloper: isDeveloper,
        isPerformer: isPerformer,
        isSupport: isSupport,
        token: token,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        bannerUrl: bannerUrl ?? this.bannerUrl,
        likesPrivacy: likesPrivacy ?? this.likesPrivacy,
        bio: bio ?? this.bio,
      );
}
