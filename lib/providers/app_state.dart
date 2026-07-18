import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';

class AppState extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  String _locale = AppStrings.en;

  ThemeMode get themeMode => _themeMode;
  String get locale => _locale;
  bool get isDark => _themeMode == ThemeMode.dark;

  AppState() {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('theme_mode');
    final savedLocale = prefs.getString('locale');
    if (savedTheme == 'light') _themeMode = ThemeMode.light;
    if (savedLocale != null) _locale = savedLocale;
    notifyListeners();
  }

  Future<void> toggleTheme(bool isDarkMode) async {
    _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', isDarkMode ? 'dark' : 'light');
  }

  Future<void> setLocale(String locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale);
  }
}

extension L10nX on BuildContext {
  /// Translates [key] using the currently selected app language.
  /// Listens for changes so widgets rebuild when the language is switched.
  String tr(String key) {
    final locale = Provider.of<AppState>(this, listen: true).locale;
    return AppStrings.t(locale, key);
  }
}
