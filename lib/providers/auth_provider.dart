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

  Future<void> logout() async {
    _user = null;
    _status = AuthStatus.unauthenticated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserKey);
    notifyListeners();
  }
}
