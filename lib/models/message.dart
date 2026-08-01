/// A single plain-text direct message between two accounts. No
/// encryption — stored and transmitted as plain text, same as every other
/// piece of user content in this app (bio, playlist names, etc).
class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String recipientId;
  final String text;
  final DateTime createdAt;

  /// Enforced by the chat composer and by backends that accept
  /// [ApiService.sendMessage] — anything longer is rejected.
  static const maxLength = 2000;

  factory DirectMessage.fromJson(Map<String, dynamic> json) => DirectMessage(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        recipientId: json['recipient_id'] as String,
        text: json['text'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (((json['created_at'] as num?) ?? 0) * 1000).round(),
          isUtc: true,
        ).toLocal(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender_id': senderId,
        'recipient_id': recipientId,
        'text': text,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch / 1000,
      };
}

/// One row in the Messages tab's conversation list: the most recent
/// message exchanged with [otherUserId], enough to render a preview
/// without fetching the whole thread. Callers join [otherUserId] against
/// the Community user list (or a direct fetch) to show a name/avatar.
class ConversationSummary {
  const ConversationSummary({
    required this.otherUserId,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastMessageFromMe,
  });

  final String otherUserId;
  final String lastMessage;
  final DateTime lastMessageAt;
  final bool lastMessageFromMe;
}
