import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple on-device cache used for requirement #7 (recently played) and
/// for persisting the logged-in user / theme / language between launches.
class CacheService {
  CacheService._internal();
  static final CacheService instance = CacheService._internal();

  static const _kRecentlyPlayed = 'recently_played_ids';
  static const _kMaxRecent = 30;

  static const _kSearchHistory = 'search_history_queries';
  static const _kMaxSearchHistory = 15;

  Future<List<String>> getRecentlyPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRecentlyPlayed);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => e as String).toList();
  }

  Future<void> addRecentlyPlayed(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getRecentlyPlayed();
    current.remove(trackId);
    current.insert(0, trackId);
    if (current.length > _kMaxRecent) {
      current.removeRange(_kMaxRecent, current.length);
    }
    await prefs.setString(_kRecentlyPlayed, jsonEncode(current));
  }

  Future<void> clearRecentlyPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRecentlyPlayed);
  }

  /// Search query history. Lives only in on-device SharedPreferences —
  /// never sent to the backend or stored in a database.
  Future<List<String>> getSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSearchHistory);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).map((e) => e as String).toList();
  }

  Future<void> addSearchHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await getSearchHistory();
    current.removeWhere((q) => q.toLowerCase() == trimmed.toLowerCase());
    current.insert(0, trimmed);
    if (current.length > _kMaxSearchHistory) {
      current.removeRange(_kMaxSearchHistory, current.length);
    }
    await prefs.setString(_kSearchHistory, jsonEncode(current));
  }

  Future<void> removeSearchHistoryItem(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getSearchHistory();
    current.removeWhere((q) => q == query);
    await prefs.setString(_kSearchHistory, jsonEncode(current));
  }

  Future<void> clearSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSearchHistory);
  }
}
