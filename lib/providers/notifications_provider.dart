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

  List<AppNotification> get items => _items;
  bool get loading => _loading;
  bool get sending => _sending;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _items = await _api.fetchNotifications();
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
