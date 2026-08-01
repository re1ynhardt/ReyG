import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../services/api_service.dart';

/// Backs the Messages tab (conversation list) and the individual chat
/// screen opened from it or from a Community profile's Message button.
/// Plain text only — no encryption.
class MessagesProvider extends ChangeNotifier {
  MessagesProvider(this._api);

  final ApiService _api;

  List<ConversationSummary> _conversations = [];
  bool _loadingConversations = false;

  // Messages for whichever chat thread is currently open, keyed by the
  // other account's id so switching between chats (or reopening one)
  // doesn't require re-fetching if we already have it cached in memory.
  final Map<String, List<DirectMessage>> _threads = {};
  bool _loadingThread = false;
  bool _sending = false;

  List<ConversationSummary> get conversations => _conversations;
  bool get loadingConversations => _loadingConversations;
  bool get loadingThread => _loadingThread;
  bool get sending => _sending;

  List<DirectMessage> messagesWith(String otherUserId) => _threads[otherUserId] ?? const [];

  Future<void> loadConversations() async {
    _loadingConversations = true;
    notifyListeners();
    try {
      _conversations = await _api.fetchConversations();
    } finally {
      _loadingConversations = false;
      notifyListeners();
    }
  }

  Future<void> loadThread(String otherUserId) async {
    _loadingThread = true;
    notifyListeners();
    try {
      _threads[otherUserId] = await _api.fetchMessages(otherUserId);
    } finally {
      _loadingThread = false;
      notifyListeners();
    }
  }

  /// Sends [text] to [otherUserId] and appends it to that thread and to
  /// the conversation list right away. Throws [ApiException] on failure
  /// (e.g. empty text) — the caller's UI is expected to show that.
  Future<void> send({required String otherUserId, required String text}) async {
    _sending = true;
    notifyListeners();
    try {
      final message = await _api.sendMessage(recipientId: otherUserId, text: text);
      _threads[otherUserId] = [...messagesWith(otherUserId), message];
      final withoutThisConvo = _conversations.where((c) => c.otherUserId != otherUserId).toList();
      _conversations = [
        ConversationSummary(
          otherUserId: otherUserId,
          lastMessage: message.text,
          lastMessageAt: message.createdAt,
          lastMessageFromMe: true,
        ),
        ...withoutThisConvo,
      ];
    } finally {
      _sending = false;
      notifyListeners();
    }
  }
}
