/// A broadcast notification, posted by a developer account and shown to
/// every user in the notifications shade (see
/// widgets/notifications_shade.dart).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (((json['created_at'] as num?) ?? 0) * 1000).round(),
          isUtc: true,
        ).toLocal(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch / 1000,
      };
}
