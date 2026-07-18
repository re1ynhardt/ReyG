import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _initial(String? name) {
    if (name == null || name.isEmpty) return '?';
    return name.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(context.tr('account'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ListTile(
            leading: CircleAvatar(child: Text(_initial(auth.user?.displayName))),
            title: Text(auth.user?.displayName ?? ''),
            subtitle: Text(auth.user?.email ?? ''),
            trailing: auth.isDeveloper
                ? Chip(
                    label: Text(context.tr('developer_account'), style: const TextStyle(fontSize: 11)),
                    avatar: const Icon(Icons.verified, size: 16),
                  )
                : null,
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(context.tr('language'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          RadioListTile<String>(
            title: const Text('English'),
            value: AppStrings.en,
            groupValue: appState.locale,
            onChanged: (v) => appState.setLocale(v!),
          ),
          RadioListTile<String>(
            title: const Text('Русский'),
            value: AppStrings.ru,
            groupValue: appState.locale,
            onChanged: (v) => appState.setLocale(v!),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(context.tr('theme'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          SwitchListTile(
            title: Text(appState.isDark ? context.tr('dark') : context.tr('light')),
            secondary: Icon(appState.isDark ? Icons.dark_mode : Icons.light_mode),
            value: appState.isDark,
            onChanged: (v) => appState.toggleTheme(v),
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(context.tr('logout'), style: const TextStyle(color: Colors.red)),
            onTap: () => auth.logout(),
          ),
        ],
      ),
    );
  }
}
