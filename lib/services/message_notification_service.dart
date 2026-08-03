import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

/// Raises a system (phone-shade) notification when a new incoming direct
/// message arrives.
///
/// IMPORTANT — this is a *local* notification, not a real push (FCM/APNs):
/// the app talks directly to Yandex Object Storage (see
/// [ApiService]/`YandexStorageApiService`) with no server component of its
/// own, and object storage has no way to wake the app or call a push
/// service when a new object appears. So instead, while the app process is
/// alive (foreground, or backgrounded but not force-quit) this polls
/// [ApiService.fetchConversations] — the same call the Messages tab
/// already polls with — and pops a native notification for whichever
/// conversation just got a new message, as long as that thread isn't the
/// one currently open on screen (see [setOpenThread]).
class MessageNotificationService {
  MessageNotificationService._();
  static final instance = MessageNotificationService._();

  static const _pollInterval = Duration(seconds: 5);

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Timer? _timer;
  String? _openThreadId;
  DateTime? _startedAt;
  final Map<String, DateTime> _lastNotified = {};

  /// Sets up the plugin + notification channel and asks for permission.
  /// Safe to call more than once.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Tells this service which chat thread (if any) is currently visible on
  /// screen, so its messages don't also pop a notification. Call with
  /// `null` when leaving [ChatScreen].
  void setOpenThread(String? otherUserId) => _openThreadId = otherUserId;

  /// Starts polling [api] for new messages addressed to [myUserId].
  /// [displayNameOf] resolves an account id to a display name for the
  /// notification title (falls back to a generic title when unknown).
  /// Safe to call again (e.g. on hot-restart of the Home screen) — just
  /// restarts the timer.
  void start(
    ApiService api,
    String myUserId, {
    String Function(String otherUserId)? displayNameOf,
  }) {
    _timer?.cancel();
    // Only notify about messages newer than "now" — an unread message
    // that was already sitting there before the app opened shouldn't pop
    // a fresh system notification too.
    _startedAt = DateTime.now();
    _timer = Timer.periodic(_pollInterval, (_) => _tick(api, displayNameOf));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick(ApiService api, String Function(String otherUserId)? displayNameOf) async {
    final startedAt = _startedAt;
    if (startedAt == null) return;
    try {
      final conversations = await api.fetchConversations();
      for (final c in conversations) {
        if (c.lastMessageFromMe) continue;
        if (c.otherUserId == _openThreadId) continue;
        if (!c.lastMessageAt.isAfter(startedAt)) continue;
        final lastNotified = _lastNotified[c.otherUserId];
        if (lastNotified != null && !c.lastMessageAt.isAfter(lastNotified)) continue;
        _lastNotified[c.otherUserId] = c.lastMessageAt;
        final title = displayNameOf?.call(c.otherUserId) ?? 'Новое сообщение';
        await _show(c.otherUserId, title, c.lastMessage);
      }
    } catch (_) {
      // Silent — same pattern as MessagesProvider's other quiet polls:
      // this just retries on the next tick.
    }
  }

  int _notificationId(String otherUserId) => otherUserId.hashCode & 0x7fffffff;

  Future<void> _show(String otherUserId, String title, String body) {
    const androidDetails = AndroidNotificationDetails(
      'messages',
      'Сообщения',
      channelDescription: 'Новые личные сообщения',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );
    return _plugin.show(_notificationId(otherUserId), title, body, details, payload: otherUserId);
  }
}
