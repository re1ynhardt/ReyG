import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';

class AppState extends ChangeNotifier {
  AppThemeOption _themeOption = AppThemeOption.dark;
  String _locale = AppStrings.en;

  AppThemeOption get themeOption => _themeOption;
  String get locale => _locale;
  bool get isDark => _themeOption.isDark;

  AppState() {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('theme_mode');
    final savedLocale = prefs.getString('locale');
    _themeOption = AppThemeOptionX.fromStorageKey(savedTheme);
    if (savedLocale != null) _locale = savedLocale;
    notifyListeners();
  }

  Future<void> setTheme(AppThemeOption option) async {
    _themeOption = option;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', option.storageKey);
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
