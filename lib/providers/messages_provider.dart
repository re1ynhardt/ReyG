import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';

/// Backs the Messages tab (conversation list) and the individual chat
/// screen opened from it or from a Community profile's Message button.
/// Always deals in plaintext — encryption (on the real backend) is
/// handled entirely inside the `ApiService` implementation.
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

  // On-device "last read" timestamp per conversation, used to derive the
  // unread badge on the Messages nav item. There's no server-side read
  // flag — a conversation counts as unread when its latest message is
  // from the other person and arrived after we last opened that thread.
  Map<String, int> _lastRead = {};
  bool _lastReadLoaded = false;

  // otherUserId -> timestamp up to which THAT account has read messages
  // I sent them (from ApiService.fetchReadReceipts). Drives the
  // sent/read ticks shown on my own messages, in both the conversation
  // list and the chat thread.
  Map<String, DateTime> _readReceipts = {};

  List<ConversationSummary> get conversations => _conversations;
  bool get loadingConversations => _loadingConversations;
  bool get loadingThread => _loadingThread;
  bool get sending => _sending;

  List<DirectMessage> messagesWith(String otherUserId) => _threads[otherUserId] ?? const [];

  /// Number of conversations with an unread incoming message. Drives the
  /// small red badge next to the "messages" bottom nav item.
  int get unreadCount => _conversations.where(isUnread).length;

  /// Whether [c]'s latest message is an unread incoming one — i.e. it's
  /// from the other person and arrived after we last opened that thread.
  bool isUnread(ConversationSummary c) {
    if (c.lastMessageFromMe) return false;
    final lastRead = _lastRead[c.otherUserId];
    return lastRead == null || c.lastMessageAt.millisecondsSinceEpoch > lastRead;
  }

  /// Whether a message I sent to [otherUserId] at [sentAt] has been read
  /// by them yet. False (single tick) if they've never opened the
  /// thread, or opened it before [sentAt].
  bool isReadByOther(String otherUserId, DateTime sentAt) {
    final readUpTo = _readReceipts[otherUserId];
    return readUpTo != null && !sentAt.isAfter(readUpTo);
  }

  Future<void> loadConversations() async {
    if (!_lastReadLoaded) {
      _lastRead = await CacheService.instance.getMessageLastRead();
      _lastReadLoaded = true;
    }
    _loadingConversations = true;
    notifyListeners();
    try {
      final results = await Future.wait([_api.fetchConversations(), _api.fetchReadReceipts()]);
      _conversations = results[0] as List<ConversationSummary>;
      _readReceipts = results[1] as Map<String, DateTime>;
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
    await markRead(otherUserId);
  }

  /// Marks [otherUserId]'s thread as read as of now, clearing its unread
  /// badge. Synced to the backend (see [ApiService.markThreadRead]) so
  /// [otherUserId] sees a read tick on the messages they sent, not just
  /// stored on this device. Called whenever that thread is opened.
  Future<void> markRead(String otherUserId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastRead[otherUserId] = now;
    notifyListeners();
    await CacheService.instance.setMessageLastRead(otherUserId, now);
    await _api.markThreadRead(otherUserId);
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
    await markRead(otherUserId);
  }
}
