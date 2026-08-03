import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/message_attachment.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/yandex_storage_api_service.dart';

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

  // IDs of messages that have been optimistically echoed into a thread
  // (see [send]) but haven't been confirmed by the backend yet — drives
  // the clock/pending tick in [ChatScreen] instead of the normal
  // sent/read one.
  final Set<String> _pendingMessageIds = {};

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

  /// Whether [messageId] is a locally-echoed message still waiting on
  /// [ApiService.sendMessage] to confirm it (see [send]).
  bool isPending(String messageId) => _pendingMessageIds.contains(messageId);

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

  bool _refreshingConversations = false;

  /// Quiet background refresh of the conversation list, used for polling
  /// (see [ChatScreen]/[MessagesScreen]) so new incoming messages show up
  /// without a full reload flicker (no loading spinner, only notifies if
  /// something actually changed).
  Future<void> refreshConversationsQuietly() async {
    if (_loadingConversations || _refreshingConversations) return;
    _refreshingConversations = true;
    try {
      final results = await Future.wait([_api.fetchConversations(), _api.fetchReadReceipts()]);
      final freshConvos = results[0] as List<ConversationSummary>;
      final freshReceipts = results[1] as Map<String, DateTime>;
      if (!_sameConversations(_conversations, freshConvos) || !mapEquals(_readReceipts, freshReceipts)) {
        _conversations = freshConvos;
        _readReceipts = freshReceipts;
        notifyListeners();
      }
    } catch (_) {
      // Silent: this is a background poll, errors just get retried next tick.
    } finally {
      _refreshingConversations = false;
    }
  }

  bool _sameConversations(List<ConversationSummary> a, List<ConversationSummary> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].otherUserId != b[i].otherUserId ||
          a[i].lastMessage != b[i].lastMessage ||
          a[i].lastMessageAt != b[i].lastMessageAt ||
          a[i].lastMessageFromMe != b[i].lastMessageFromMe) {
        return false;
      }
    }
    return true;
  }

  /// Loads [otherUserId]'s thread. If we have a cached copy (in-memory or
  /// on-device, see [CacheService.getCachedMessages]) it's shown right away
  /// so the chat opens instantly at the last known message instead of
  /// waiting on the network; a fresh copy is then fetched in the background
  /// and used to update both the in-memory thread and the on-device cache.
  Future<void> loadThread(String otherUserId) async {
    if (!_threads.containsKey(otherUserId)) {
      final cached = await CacheService.instance.getCachedMessages(otherUserId);
      if (cached.isNotEmpty) {
        _threads[otherUserId] = cached;
        notifyListeners();
      }
    }
    _loadingThread = messagesWith(otherUserId).isEmpty;
    if (_loadingThread) notifyListeners();
    try {
      final fresh = await _api.fetchMessages(otherUserId);
      _threads[otherUserId] = fresh;
      // Fire-and-forget: don't block the UI on the cache write.
      unawaited(CacheService.instance.setCachedMessages(otherUserId, fresh));
    } finally {
      _loadingThread = false;
      notifyListeners();
    }
    await markRead(otherUserId);
  }

  bool _refreshingThread = false;

  /// Quiet background refresh of an already-open thread, used for polling
  /// (see [ChatScreen]) so incoming messages *and* read ticks (has the
  /// other person seen what I sent yet) update without leaving/reopening
  /// the chat. No loading spinner; only notifies for whichever part
  /// actually changed.
  Future<void> refreshThreadQuietly(String otherUserId) async {
    // Guards against overlap: at a 1s poll interval a slow response could
    // otherwise still be in flight when the next tick fires.
    if (_loadingThread || _refreshingThread) return;
    _refreshingThread = true;
    try {
      final results = await Future.wait([
        _api.fetchMessages(otherUserId),
        _api.fetchReadReceipts(),
      ]);
      final fetched = results[0] as List<DirectMessage>;
      final freshReceipts = results[1] as Map<String, DateTime>;
      final current = messagesWith(otherUserId);
      // A message just sent (see [send]) may still be in flight — it
      // won't be in `fetched` yet since the backend hasn't confirmed it.
      // Keep it appended so it doesn't flicker away mid-send only to
      // reappear once the next poll picks up the confirmed copy.
      final stillPending = current.where((m) => _pendingMessageIds.contains(m.id));
      final fresh = [...fetched, ...stillPending];
      var changed = false;
      var messagesChanged = false;

      if (fresh.length != current.length ||
          (fresh.isNotEmpty && current.isNotEmpty && fresh.last.id != current.last.id)) {
        _threads[otherUserId] = fresh;
        unawaited(CacheService.instance.setCachedMessages(otherUserId, fetched));
        changed = true;
        messagesChanged = true;
      }
      if (freshReceipts[otherUserId] != _readReceipts[otherUserId]) {
        _readReceipts = freshReceipts;
        changed = true;
      }

      if (changed) notifyListeners();
      if (messagesChanged) await markRead(otherUserId);
    } catch (_) {
      // Silent: this is a background poll, errors just get retried next tick.
    } finally {
      _refreshingThread = false;
    }
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

  /// Uploads [localImagePath] and returns a [MessageAttachment.image]
  /// ready to stage in the composer (same shape as picking a track or
  /// playlist in [AttachPickerSheet]). Only supported when running
  /// against [YandexStorageApiService] — mock/legacy backends don't
  /// implement chat image uploads, and this throws for them instead.
  Future<MessageAttachment> uploadImageAttachment(String localImagePath) async {
    final api = _api;
    if (api is! YandexStorageApiService) {
      throw StateError('Sending images isn\'t supported on this backend');
    }
    final url = await api.uploadChatImage(localImagePath);
    return MessageAttachment.image(id: DateTime.now().microsecondsSinceEpoch.toString(), coverUrl: url);
  }

  /// Uploads [localAudioPath] and returns a [MessageAttachment.voice]
  /// ready to send — the recording is encrypted client-side (see
  /// [YandexStorageApiService.uploadChatVoice]) so nobody without the
  /// keys either side of this conversation holds can listen to it, not
  /// even someone with direct access to the storage bucket. Only
  /// supported against [YandexStorageApiService], same restriction as
  /// [uploadImageAttachment].
  Future<MessageAttachment> uploadVoiceAttachment(
    String localAudioPath, {
    required String recipientId,
    required int durationSeconds,
  }) async {
    final api = _api;
    if (api is! YandexStorageApiService) {
      throw StateError('Sending voice messages isn\'t supported on this backend');
    }
    final url = await api.uploadChatVoice(localAudioPath, recipientId: recipientId);
    return MessageAttachment.voice(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      audioUrl: url,
      durationSeconds: durationSeconds,
    );
  }

  /// Downloads and decrypts a [MessageAttachment.voice]'s recording,
  /// returning the raw playable audio bytes. [otherUserId] is whichever
  /// account is on the other side of this thread (works the same
  /// whether this account sent or received the message).
  Future<Uint8List> downloadDecryptedVoice(String audioUrl, {required String otherUserId}) async {
    final api = _api;
    if (api is! YandexStorageApiService) {
      throw StateError('Voice messages aren\'t supported on this backend');
    }
    return api.downloadChatVoice(audioUrl, otherUserId: otherUserId);
  }

  /// Developer-only, Yandex Storage-only (see [uploadImageAttachment]
  /// above for why this doesn't live on [ApiService]): wipes every
  /// direct-message conversation for every user, text and attachments
  /// (including the actual image objects in the bucket) alike. Returns
  /// how many message rows were deleted, for the confirmation snackbar.
  Future<int> wipeAllMessages() async {
    final api = _api;
    if (api is! YandexStorageApiService) {
      throw StateError('Wiping all messages isn\'t supported on this backend');
    }
    final count = await api.wipeAllDirectMessages();
    _conversations = [];
    _threads.clear();
    _pendingMessageIds.clear();
    await CacheService.instance.clearAllCachedMessageThreads();
    notifyListeners();
    return count;
  }

  /// Sends [text] to [otherUserId] as [myId]. The message is echoed into
  /// the thread immediately under a temporary local id — shown with a
  /// pending/clock tick via [isPending] — so it's visible right away
  /// instead of waiting on the round-trip to storage. Once
  /// [ApiService.sendMessage] confirms it, the temporary entry is
  /// swapped for the real one; on failure it's removed again and the
  /// error is rethrown for the caller's UI to handle (e.g. restoring the
  /// composer text), same as before.
  Future<void> send({required String otherUserId, required String text, required String myId}) async {
    final localId = 'pending_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = DirectMessage(
      id: localId,
      senderId: myId,
      recipientId: otherUserId,
      text: text,
      createdAt: DateTime.now(),
    );
    _pendingMessageIds.add(localId);
    _threads[otherUserId] = [...messagesWith(otherUserId), optimistic];
    _sending = true;
    notifyListeners();
    try {
      final message = await _api.sendMessage(recipientId: otherUserId, text: text);
      _threads[otherUserId] = [
        for (final m in messagesWith(otherUserId))
          if (m.id == localId) message else m,
      ];
      unawaited(CacheService.instance.setCachedMessages(otherUserId, _threads[otherUserId]!));
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
    } catch (_) {
      _threads[otherUserId] = messagesWith(otherUserId).where((m) => m.id != localId).toList();
      rethrow;
    } finally {
      _pendingMessageIds.remove(localId);
      _sending = false;
      notifyListeners();
    }
    await markRead(otherUserId);
  }
}
