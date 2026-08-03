import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../../providers/app_state.dart';
import '../../theme/app_theme.dart';

/// Dedicated screen listing every selectable [AppThemeOption]. Reached from
/// the "App theme" category in Settings, so the main Settings list only
/// shows a single entry point instead of the full theme list inline.
class ThemesScreen extends StatelessWidget {
  const ThemesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('all_themes'))),
      body: ListView(
        children: [
          const SizedBox(height: 4),
          for (final option in AppThemeOption.values)
            RadioListTile<AppThemeOption>(
              title: Text(context.tr(option.labelKey)),
              secondary: CircleAvatar(
                radius: 16,
                backgroundColor: option.swatch,
                child: Icon(option.icon, size: 16, color: option.isDark ? Colors.white : Colors.black87),
              ),
              value: option,
              groupValue: appState.themeOption,
              onChanged: (v) => appState.setTheme(v!),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
