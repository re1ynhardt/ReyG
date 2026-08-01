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

  // Ruby theme — dark, dramatic garnet-red.
  static const rubyAccent = Color(0xFFE0334D);
  static const rubyBg = Color(0xFF1A0508);
  static const rubySurface = Color(0xFF260A0F);
  static const rubyCard = Color(0xFF34121A);

  // Emerald theme — dark, deep forest green.
  static const emeraldAccent = Color(0xFF2ECC8F);
  static const emeraldBg = Color(0xFF071A12);
  static const emeraldSurface = Color(0xFF0D2A1C);
  static const emeraldCard = Color(0xFF123825);

  // Wood theme — dark, warm walnut-brown.
  static const woodAccent = Color(0xFFC9975B);
  static const woodBg = Color(0xFF221510);
  static const woodSurface = Color(0xFF2E1E16);
  static const woodCard = Color(0xFF3B271C);

  // Clouds theme — light, soft neutral grey.
  static const cloudsAccent = Color(0xFF78909C);
  static const cloudsBg = Color(0xFFEDEEF0);
  static const cloudsSurface = Color(0xFFE1E3E6);
  static const cloudsCard = Color(0xFFD5D8DC);

  // Rain theme — dark, deep navy-blue.
  static const rainAccent = Color(0xFF5B8DEF);
  static const rainBg = Color(0xFF0A0F1C);
  static const rainSurface = Color(0xFF121A2B);
  static const rainCard = Color(0xFF1A2438);

  // Violet theme — dark, vivid violet (distinct from the muted "purple").
  static const violetAccent = Color(0xFF9D4EDD);
  static const violetBg = Color(0xFF160B23);
  static const violetSurface = Color(0xFF211231);
  static const violetCard = Color(0xFF2C1A40);

  // Pink theme — light, soft rose-pink.
  static const pinkAccent = Color(0xFFE8578A);
  static const pinkBg = Color(0xFFFFF0F4);
  static const pinkSurface = Color(0xFFFDE1EA);
  static const pinkCard = Color(0xFFFBD3E1);

  // Bubbles theme — light, playful aqua with floating-bubble decoration.
  static const bubblesAccent = Color(0xFF00BCD4);
  static const bubblesBg = Color(0xFFE3F6F9);
  static const bubblesSurface = Color(0xFFD3EFF4);
  static const bubblesCard = Color(0xFFC2E9F0);

  // AMOLED theme — true black everywhere (battery-saving on OLED
  // screens), cards are the same near-black as the background and are
  // defined only by a hairline white border instead of a lighter fill.
  static const amoledSurface = Color(0xFF000000);
  static const amoledCard = Color(0xFF0A0A0A);
}

/// All selectable app themes. Each has its own background/card/accent
/// palette and is fully independent — there is no separate "dark mode"
/// switch layered on top.
enum AppThemeOption {
  dark,
  amoled,
  light,
  peach,
  sky,
  purple,
  ruby,
  emerald,
  wood,
  clouds,
  rain,
  violet,
  pink,
  bubbles,
}

extension AppThemeOptionX on AppThemeOption {
  /// Stable key used for persistence (SharedPreferences).
  String get storageKey {
    switch (this) {
      case AppThemeOption.dark:
        return 'dark';
      case AppThemeOption.amoled:
        return 'amoled';
      case AppThemeOption.light:
        return 'light';
      case AppThemeOption.peach:
        return 'peach';
      case AppThemeOption.sky:
        return 'sky';
      case AppThemeOption.purple:
        return 'purple';
      case AppThemeOption.ruby:
        return 'ruby';
      case AppThemeOption.emerald:
        return 'emerald';
      case AppThemeOption.wood:
        return 'wood';
      case AppThemeOption.clouds:
        return 'clouds';
      case AppThemeOption.rain:
        return 'rain';
      case AppThemeOption.violet:
        return 'violet';
      case AppThemeOption.pink:
        return 'pink';
      case AppThemeOption.bubbles:
        return 'bubbles';
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
      case AppThemeOption.amoled:
      case AppThemeOption.purple:
      case AppThemeOption.sky:
      case AppThemeOption.ruby:
      case AppThemeOption.emerald:
      case AppThemeOption.wood:
      case AppThemeOption.rain:
      case AppThemeOption.violet:
        return true;
      case AppThemeOption.light:
      case AppThemeOption.peach:
      case AppThemeOption.clouds:
      case AppThemeOption.pink:
      case AppThemeOption.bubbles:
        return false;
    }
  }

  /// Small swatch color shown next to the theme name in Settings.
  Color get swatch {
    switch (this) {
      case AppThemeOption.dark:
        return const Color(0xFF1E1E1E);
      case AppThemeOption.amoled:
        return Colors.black;
      case AppThemeOption.light:
        return const Color(0xFFECECEE);
      case AppThemeOption.peach:
        return AppColors.peachAccent;
      case AppThemeOption.sky:
        return AppColors.skyAccent;
      case AppThemeOption.purple:
        return AppColors.purpleAccent;
      case AppThemeOption.ruby:
        return AppColors.rubyAccent;
      case AppThemeOption.emerald:
        return AppColors.emeraldAccent;
      case AppThemeOption.wood:
        return AppColors.woodAccent;
      case AppThemeOption.clouds:
        return AppColors.cloudsAccent;
      case AppThemeOption.rain:
        return AppColors.rainAccent;
      case AppThemeOption.violet:
        return AppColors.violetAccent;
      case AppThemeOption.pink:
        return AppColors.pinkAccent;
      case AppThemeOption.bubbles:
        return AppColors.bubblesAccent;
    }
  }

  IconData get icon {
    switch (this) {
      case AppThemeOption.dark:
        return Icons.dark_mode;
      case AppThemeOption.amoled:
        return Icons.brightness_1;
      case AppThemeOption.light:
        return Icons.light_mode;
      case AppThemeOption.peach:
        return Icons.wb_twilight;
      case AppThemeOption.sky:
        return Icons.cloud_outlined;
      case AppThemeOption.purple:
        return Icons.diamond_outlined;
      case AppThemeOption.ruby:
        return Icons.favorite;
      case AppThemeOption.emerald:
        return Icons.eco;
      case AppThemeOption.wood:
        return Icons.park;
      case AppThemeOption.clouds:
        return Icons.cloud;
      case AppThemeOption.rain:
        return Icons.water_drop;
      case AppThemeOption.violet:
        return Icons.color_lens;
      case AppThemeOption.pink:
        return Icons.favorite_border;
      case AppThemeOption.bubbles:
        return Icons.bubble_chart;
    }
  }

  ThemeData get themeData {
    switch (this) {
      case AppThemeOption.dark:
        return AppTheme.dark;
      case AppThemeOption.amoled:
        return AppTheme.amoled;
      case AppThemeOption.light:
        return AppTheme.light;
      case AppThemeOption.peach:
        return AppTheme.peach;
      case AppThemeOption.sky:
        return AppTheme.sky;
      case AppThemeOption.purple:
        return AppTheme.purple;
      case AppThemeOption.ruby:
        return AppTheme.ruby;
      case AppThemeOption.emerald:
        return AppTheme.emerald;
      case AppThemeOption.wood:
        return AppTheme.wood;
      case AppThemeOption.clouds:
        return AppTheme.clouds;
      case AppThemeOption.rain:
        return AppTheme.rain;
      case AppThemeOption.violet:
        return AppTheme.violet;
      case AppThemeOption.pink:
        return AppTheme.pink;
      case AppThemeOption.bubbles:
        return AppTheme.bubbles;
    }
  }
}

/// Readable foreground for text/icons painted directly on a solid
/// [background] fill (badges, filled pill buttons, tab indicators). Most
/// theme accents are saturated enough that hardcoding white works fine,
/// but the AMOLED theme's accent is pure white, so those spots need to
/// flip to black instead — this keeps that decision in one place.
Color onColor(Color background) => background.computeLuminance() > 0.55 ? Colors.black : Colors.white;

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

  /// AMOLED — pure black everywhere, including cards (which sit at the
  /// same near-black as the background and are only set apart by a thin
  /// white-ish border), for maximum battery savings on OLED screens.
  /// Unlike the other themes, there's no separate accent color here —
  /// white is both the primary and secondary color, so play buttons,
  /// active states, and the progress bar are all white instead of red.
  static ThemeData get amoled {
    const bg = Colors.black;
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: Colors.white,
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        secondary: Colors.white,
        surface: AppColors.amoledSurface,
      ),
      cardColor: AppColors.amoledCard,
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
        fillColor: AppColors.amoledCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        hintStyle: const TextStyle(color: Colors.white38),
      ),
      // Cards would otherwise be visually indistinguishable from the
      // pure-black background, so give them a hairline white border to
      // read as "inserts" instead of relying on a fill-color difference.
      cardTheme: CardThemeData(
        color: AppColors.amoledCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.white24),
        ),
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

  /// Shared skeleton for the dark, saturated-accent themes (ruby, emerald,
  /// wood, rain, violet) — only the palette changes between them.
  static ThemeData _darkAccent({
    required Color bg,
    required Color surface,
    required Color card,
    required Color accent,
  }) {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      primaryColor: accent,
      colorScheme: ColorScheme.dark(primary: accent, secondary: accent, surface: surface),
      cardColor: card,
      dividerColor: Colors.white24,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: accent,
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
        activeTrackColor: accent,
        inactiveTrackColor: Colors.white24,
        thumbColor: accent,
        overlayColor: accent.withOpacity(0.2),
        trackHeight: 3,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        hintStyle: const TextStyle(color: Colors.white38),
      ),
      useMaterial3: true,
    );
  }

  /// Shared skeleton for the light, saturated-accent themes (clouds, pink,
  /// bubbles) — only the palette + ink color changes between them.
  static ThemeData _lightAccent({
    required Color bg,
    required Color surface,
    required Color card,
    required Color accent,
    required Color ink,
  }) {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      primaryColor: accent,
      colorScheme: ColorScheme.light(primary: accent, secondary: accent, surface: surface),
      cardColor: card,
      dividerColor: ink.withOpacity(0.16),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: ink, fontSize: 28, fontWeight: FontWeight.bold),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bg,
        selectedItemColor: accent,
        unselectedItemColor: ink.withOpacity(0.55),
        type: BottomNavigationBarType.fixed,
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: ink),
        bodyMedium: TextStyle(color: ink),
        titleMedium: TextStyle(color: ink, fontWeight: FontWeight.w600),
      ).apply(bodyColor: ink, displayColor: ink),
      iconTheme: IconThemeData(color: ink),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: card,
        thumbColor: accent,
        overlayColor: accent.withOpacity(0.2),
        trackHeight: 3,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        hintStyle: TextStyle(color: ink.withOpacity(0.55)),
      ),
      useMaterial3: true,
    );
  }

  /// Ruby — dark, dramatic garnet-red.
  static ThemeData get ruby => _darkAccent(
        bg: AppColors.rubyBg,
        surface: AppColors.rubySurface,
        card: AppColors.rubyCard,
        accent: AppColors.rubyAccent,
      );

  /// Emerald — dark, deep forest green.
  static ThemeData get emerald => _darkAccent(
        bg: AppColors.emeraldBg,
        surface: AppColors.emeraldSurface,
        card: AppColors.emeraldCard,
        accent: AppColors.emeraldAccent,
      );

  /// Wood — dark, warm walnut-brown.
  static ThemeData get wood => _darkAccent(
        bg: AppColors.woodBg,
        surface: AppColors.woodSurface,
        card: AppColors.woodCard,
        accent: AppColors.woodAccent,
      );

  /// Rain — dark, deep navy-blue.
  static ThemeData get rain => _darkAccent(
        bg: AppColors.rainBg,
        surface: AppColors.rainSurface,
        card: AppColors.rainCard,
        accent: AppColors.rainAccent,
      );

  /// Violet — dark, vivid violet (distinct from the muted charcoal "purple").
  static ThemeData get violet => _darkAccent(
        bg: AppColors.violetBg,
        surface: AppColors.violetSurface,
        card: AppColors.violetCard,
        accent: AppColors.violetAccent,
      );

  /// Clouds — light, soft neutral grey.
  static ThemeData get clouds => _lightAccent(
        bg: AppColors.cloudsBg,
        surface: AppColors.cloudsSurface,
        card: AppColors.cloudsCard,
        accent: AppColors.cloudsAccent,
        ink: const Color(0xFF2E3236),
      );

  /// Pink — light, soft rose-pink.
  static ThemeData get pink => _lightAccent(
        bg: AppColors.pinkBg,
        surface: AppColors.pinkSurface,
        card: AppColors.pinkCard,
        accent: AppColors.pinkAccent,
        ink: const Color(0xFF4A2233),
      );

  /// Bubbles — light, playful aqua. Paired with a floating-bubble
  /// background decoration, see [BubblesBackground].
  static ThemeData get bubbles => _lightAccent(
        bg: AppColors.bubblesBg,
        surface: AppColors.bubblesSurface,
        card: AppColors.bubblesCard,
        accent: AppColors.bubblesAccent,
        ink: const Color(0xFF0E3438),
      );
}
