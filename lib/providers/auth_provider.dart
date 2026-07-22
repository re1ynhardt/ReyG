import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._api) {
    _restoreSession();
  }

  final ApiService _api;

  AppUser? _user;
  AuthStatus _status = AuthStatus.unknown;
  String? _error;
  bool _busy = false;

  AppUser? get user => _user;
  AuthStatus get status => _status;
  String? get error => _error;
  bool get busy => _busy;
  bool get isDeveloper => _user?.isDeveloper ?? false;

  static const _kUserKey = 'current_user';

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUserKey);
    if (raw != null) {
      _user = AppUser.fromJson(jsonDecode(raw));
      _api.restoreSession(_user!);
      _status = AuthStatus.authenticated;
    } else {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final user = await _api.login(email: email, password: password);
      await _persist(user);
      _status = AuthStatus.authenticated;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> register(String email, String password, String displayName) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final user = await _api.register(email: email, password: password, displayName: displayName);
      await _persist(user);
      _status = AuthStatus.authenticated;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _persist(AppUser user) async {
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserKey, jsonEncode(user.toJson()));
  }

  /// Uploads a new avatar for the current user and persists the updated
  /// profile locally so it survives app restarts. Throws [ApiException] if
  /// the backend rejects the file (e.g. over the 5 MB limit) — callers
  /// should surface that message to the user.
  Future<void> uploadAvatar(String localImagePath) async {
    _busy = true;
    notifyListeners();
    try {
      final updated = await _api.uploadAvatar(localImagePath);
      await _persist(updated);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Updates who can see the current user's liked tracks and playlists
  /// (see [LikesPrivacy]) and persists the change locally. Throws
  /// [ApiException] on failure.
  Future<void> setLikesPrivacy(String privacy) async {
    _busy = true;
    notifyListeners();
    try {
      final updated = await _api.setLikesPrivacy(privacy);
      await _persist(updated);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Updates the current user's profile description (shown under their
  /// avatar on their Community profile) and persists it locally. Throws
  /// [ApiException] if [bio] is longer than [AppUser.bioMaxLength].
  Future<void> setBio(String bio) async {
    _busy = true;
    notifyListeners();
    try {
      final updated = await _api.setBio(bio);
      await _persist(updated);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Changes the current user's display name (nickname) and persists it
  /// locally. Throws [ApiException] if the new name is empty (after
  /// trimming) or longer than [AppUser.displayNameMaxLength].
  Future<void> setDisplayName(String displayName) async {
    _busy = true;
    notifyListeners();
    try {
      final updated = await _api.setDisplayName(displayName);
      await _persist(updated);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Changes the current user's password. No old password is required —
  /// the request rides on the already-authenticated session. Throws
  /// [ApiException] on failure (e.g. empty password).
  Future<void> setPassword(String newPassword) async {
    _busy = true;
    notifyListeners();
    try {
      await _api.setPassword(newPassword);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _user = null;
    _status = AuthStatus.unauthenticated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserKey);
    notifyListeners();
  }
}
