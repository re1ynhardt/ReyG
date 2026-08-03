/// A single direct message between two accounts. [text] is always the
/// plaintext by the time it reaches the UI — [YandexStorageApiService]
/// (the real backend) end-to-end encrypts the message body in transit
/// and at rest using `E2EEService`, and decrypts it again before
/// returning a [DirectMessage] from `ApiService.fetchMessages` /
/// `ApiService.fetchConversations`, so no UI code needs to know this
/// happened. Other `ApiService` implementations (mock, legacy) are not
/// in scope for this and still send plain text as-is.
class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.text,
    required this.createdAt,
    this.editedAt,
  });

  final String id;
  final String senderId;
  final String recipientId;
  final String text;
  final DateTime createdAt;
  /// When this message was last edited (see
  /// `YandexStorageApiService.editMessage`), or null if it never was.
  /// Only ever set by the sender — the other side just sees the updated
  /// [text] plus this timestamp for the "edited" label.
  final DateTime? editedAt;

  /// Enforced by the chat composer and by backends that accept
  /// [ApiService.sendMessage] — anything longer is rejected. Sized to
  /// comfortably fit an encoded `MessageAttachment` (see
  /// message_attachment.dart) for a large playlist, on top of normal
  /// typed messages.
  static const maxLength = 8000;

  factory DirectMessage.fromJson(Map<String, dynamic> json) => DirectMessage(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        recipientId: json['recipient_id'] as String,
        text: json['text'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (((json['created_at'] as num?) ?? 0) * 1000).round(),
          isUtc: true,
        ).toLocal(),
        editedAt: json['edited_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                ((json['edited_at'] as num) * 1000).round(),
                isUtc: true,
              ).toLocal(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender_id': senderId,
        'recipient_id': recipientId,
        'text': text,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch / 1000,
        if (editedAt != null) 'edited_at': editedAt!.toUtc().millisecondsSinceEpoch / 1000,
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
