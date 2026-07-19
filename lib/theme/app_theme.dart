import 'package:flutter/material.dart';

/// Requirement #13:
///  - Dark theme  = black background with white inserts (cards, text, icons).
///  - Light theme = white background with grey inserts (cards, dividers).
/// A single accent color (Apple-Music-style red/pink) is reused in both
/// themes purely for the play button / active states / progress bar.
class AppColors {
  static const accent = Color(0xFFFA2D48); // Apple-Music-esque red/pink
  static const darkSurface = Color(0xFF141414);
  static const darkCard = Color(0xFF1E1E1E);
  static const lightSurface = Color(0xFFF4F4F5);
  static const lightCard = Color(0xFFECECEE);

  // Peach theme (light, warm)
  static const peachAccent = Color(0xFFFF7A59);
  static const peachBg = Color(0xFFFFF3EC);
  static const peachSurface = Color(0xFFFFE7DA);
  static const peachCard = Color(0xFFFFDCC9);

  // Sky theme — dark, premium slate-grey with only a whisper of blue.
  static const skyAccent = Color(0xFF93A2AF);
  static const skyBg = Color(0xFF14171B);
  static const skySurface = Color(0xFF1C2025);
  static const skyCard = Color(0xFF262B31);

  // Purple theme — charcoal-plum, desaturated toward grey for a premium look.
  static const purpleAccent = Color(0xFFA79BB8);
  static const purpleBg = Color(0xFF17161B);
  static const purpleSurface = Color(0xFF201E24);
  static const purpleCard = Color(0xFF2A272E);
}

/// All selectable app themes. Each has its own background/card/accent
/// palette and is fully independent — there is no separate "dark mode"
/// switch layered on top.
enum AppThemeOption { dark, light, peach, sky, purple }

extension AppThemeOptionX on AppThemeOption {
  /// Stable key used for persistence (SharedPreferences).
  String get storageKey {
    switch (this) {
      case AppThemeOption.dark:
        return 'dark';
      case AppThemeOption.light:
        return 'light';
      case AppThemeOption.peach:
        return 'peach';
      case AppThemeOption.sky:
        return 'sky';
      case AppThemeOption.purple:
        return 'purple';
    }
  }

  static AppThemeOption fromStorageKey(String? key) {
    return AppThemeOption.values.firstWhere(
      (t) => t.storageKey == key,
      orElse: () => AppThemeOption.dark,
    );
  }

  /// Localization key for the theme's display name (see AppStrings).
  String get labelKey => 'theme_$storageKey';

  bool get isDark {
    switch (this) {
      case AppThemeOption.dark:
      case AppThemeOption.purple:
      case AppThemeOption.sky:
        return true;
      case AppThemeOption.light:
      case AppThemeOption.peach:
        return false;
    }
  }

  /// Small swatch color shown next to the theme name in Settings.
  Color get swatch {
    switch (this) {
      case AppThemeOption.dark:
        return const Color(0xFF1E1E1E);
      case AppThemeOption.light:
        return const Color(0xFFECECEE);
      case AppThemeOption.peach:
        return AppColors.peachAccent;
      case AppThemeOption.sky:
        return AppColors.skyAccent;
      case AppThemeOption.purple:
        return AppColors.purpleAccent;
    }
  }

  IconData get icon {
    switch (this) {
      case AppThemeOption.dark:
        return Icons.dark_mode;
      case AppThemeOption.light:
        return Icons.light_mode;
      case AppThemeOption.peach:
        return Icons.wb_twilight;
      case AppThemeOption.sky:
        return Icons.cloud_outlined;
      case AppThemeOption.purple:
        return Icons.diamond_outlined;
    }
  }

  ThemeData get themeData {
    switch (this) {
      case AppThemeOption.dark:
        return AppTheme.dark;
      case AppThemeOption.light:
        return AppTheme.light;
      case AppThemeOption.peach:
        return AppTheme.peach;
      case AppThemeOption.sky:
        return AppTheme.sky;
      case AppThemeOption.purple:
        return AppTheme.purple;
    }
  }
}

class AppTheme {
  static ThemeData get dark {
    const bg = Colors.black;
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: Colors.white,
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        secondary: AppColors.accent,
        surface: AppColors.darkSurface,
      ),
      cardColor: AppColors.darkCard,
      dividerColor: Colors.white24,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.black,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white),
        titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ).apply(bodyColor: Colors.white, displayColor: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white),
      sliderTheme: SliderThemeData(
        activeTrackColor: Colors.white,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        overlayColor: Colors.white24,
        trackHeight: 3,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        hintStyle: const TextStyle(color: Colors.white38),
      ),
      useMaterial3: true,
    );
  }

  static ThemeData get light {
    const bg = Colors.white;
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      primaryColor: Colors.black,
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        secondary: AppColors.accent,
        surface: AppColors.lightSurface,
      ),
      cardColor: AppColors.lightCard,
      dividerColor: Colors.black12,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: Colors.black, fontSize: 28, fontWeight: FontWeight.bold),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.black38,
        type: BottomNavigationBarType.fixed,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.black),
        bodyMedium: TextStyle(color: Colors.black),
        titleMedium: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
      ).apply(bodyColor: Colors.black, displayColor: Colors.black),
      iconTheme: const IconThemeData(color: Colors.black),
      sliderTheme: SliderThemeData(
        activeTrackColor: Colors.black,
        inactiveTrackColor: Colors.black12,
        thumbColor: Colors.black,
        overlayColor: Colors.black12,
        trackHeight: 3,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        hintStyle: const TextStyle(color: Colors.black38),
      ),
      useMaterial3: true,
    );
  }

  /// Peach — light & warm (peachy background, coral-orange accent).
  static ThemeData get peach {
    const bg = AppColors.peachBg;
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      primaryColor: AppColors.peachAccent,
      colorScheme: const ColorScheme.light(
        primary: AppColors.peachAccent,
        secondary: AppColors.peachAccent,
        surface: AppColors.peachSurface,
      ),
      cardColor: AppColors.peachCard,
      dividerColor: const Color(0x33995C3D),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: Color(0xFF3D2418),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: Color(0xFF3D2418), fontSize: 28, fontWeight: FontWeight.bold),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bg,
        selectedItemColor: AppColors.peachAccent,
        unselectedItemColor: Color(0x993D2418),
        type: BottomNavigationBarType.fixed,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Color(0xFF3D2418)),
        bodyMedium: TextStyle(color: Color(0xFF3D2418)),
        titleMedium: TextStyle(color: Color(0xFF3D2418), fontWeight: FontWeight.w600),
      ).apply(bodyColor: const Color(0xFF3D2418), displayColor: const Color(0xFF3D2418)),
      iconTheme: const IconThemeData(color: Color(0xFF3D2418)),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.peachAccent,
        inactiveTrackColor: AppColors.peachCard,
        thumbColor: AppColors.peachAccent,
        overlayColor: AppColors.peachAccent.withOpacity(0.2),
        trackHeight: 3,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.peachAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.peachCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        hintStyle: const TextStyle(color: Color(0x993D2418)),
      ),
      useMaterial3: true,
    );
  }

  /// Sky — dark, cool slate blue-grey.
  static ThemeData get sky {
    const bg = AppColors.skyBg;
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: AppColors.skyAccent,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.skyAccent,
        secondary: AppColors.skyAccent,
        surface: AppColors.skySurface,
      ),
      cardColor: AppColors.skyCard,
      dividerColor: Colors.white24,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.skyCard,
        selectedItemColor: AppColors.skyAccent,
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white),
        titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ).apply(bodyColor: Colors.white, displayColor: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.skyAccent,
        inactiveTrackColor: Colors.white24,
        thumbColor: AppColors.skyAccent,
        overlayColor: AppColors.skyAccent.withOpacity(0.2),
        trackHeight: 3,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.skyAccent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.skyCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        hintStyle: const TextStyle(color: Colors.white38),
      ),
      useMaterial3: true,
    );
  }

  /// Purple — dark & rich violet.
  static ThemeData get purple {
    const bg = AppColors.purpleBg;
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: AppColors.purpleAccent,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.purpleAccent,
        secondary: AppColors.purpleAccent,
        surface: AppColors.purpleSurface,
      ),
      cardColor: AppColors.purpleCard,
      dividerColor: Colors.white24,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.purpleCard,
        selectedItemColor: AppColors.purpleAccent,
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white),
        titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ).apply(bodyColor: Colors.white, displayColor: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.purpleAccent,
        inactiveTrackColor: Colors.white24,
        thumbColor: AppColors.purpleAccent,
        overlayColor: AppColors.purpleAccent.withOpacity(0.2),
        trackHeight: 3,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.purpleAccent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.purpleCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        hintStyle: const TextStyle(color: Colors.white38),
      ),
      useMaterial3: true,
    );
  }
}
