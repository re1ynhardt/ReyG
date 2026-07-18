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
}
