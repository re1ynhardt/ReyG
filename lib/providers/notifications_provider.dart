import 'package:flutter/foundation.dart';
import '../models/app_notification.dart';
import '../services/api_service.dart';

/// Backs the notifications shade off the Home screen, plus the
/// developer-only "send notification" action in Settings.
class NotificationsProvider extends ChangeNotifier {
  NotificationsProvider(this._api);

  final ApiService _api;

  List<AppNotification> _items = [];
  bool _loading = false;
  bool _sending = false;
  DateTime? _lastLoadedAt;

  // Short TTL: the shade is a modal that gets rebuilt from scratch every
  // time the bell icon is tapped, so without this a user opening/closing
  // it repeatedly within the same session re-fetches every single time.
  // Kept short (not the usual cache duration) since stale notifications
  // are more noticeable/confusing than stale library data.
  static const _ttl = Duration(minutes: 2);

  List<AppNotification> get items => _items;
  bool get loading => _loading;
  bool get sending => _sending;

  /// Loads notifications, but skips the network call if we already fetched
  /// within [_ttl] — the shade calls this every time it's opened. Pass
  /// [force] to always hit the network (used for pull-to-refresh).
  Future<void> load({bool force = false}) async {
    if (!force && _lastLoadedAt != null && DateTime.now().difference(_lastLoadedAt!) < _ttl) {
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      _items = await _api.fetchNotifications();
      _lastLoadedAt = DateTime.now();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Developer-only — the backend rejects this for any other account
  /// type. Throws [ApiException] on failure (e.g. empty title, or not a
  /// developer account).
  Future<void> send({required String title, required String body}) async {
    _sending = true;
    notifyListeners();
    try {
      final notification = await _api.sendNotification(title: title, body: body);
      _items = [notification, ..._items];
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Developer-only — the backend rejects this for any other account
  /// type. Removes the notification locally right away (optimistic);
  /// restores it if the backend call fails.
  Future<void> delete(String id) async {
    final removed = _items.firstWhere((n) => n.id == id);
    final index = _items.indexOf(removed);
    _items = _items.where((n) => n.id != id).toList();
    notifyListeners();
    try {
      await _api.deleteNotification(id);
    } catch (_) {
      _items = [..._items]..insert(index, removed);
      notifyListeners();
      rethrow;
    }
  }
}
