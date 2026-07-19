import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _maxAvatarBytes = 5 * 1024 * 1024;

  bool _uploadingAvatar = false;

  String _initial(String? name) {
    if (name == null || name.isEmpty) return '?';
    return name.substring(0, 1).toUpperCase();
  }

  /// Same lookup as `context.tr()`, but reads the locale without
  /// subscribing to changes — safe to call from inside async event
  /// handlers (after an `await`), where `context.tr()`'s `listen: true`
  /// would trip Provider's "used outside build" assertion.
  String _trStatic(BuildContext context, String key) {
    final locale = context.read<AppState>().locale;
    return AppStrings.t(locale, key);
  }

  Future<void> _pickAndUploadAvatar() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final picked = result?.files.single;
    if (picked?.path == null) return;

    if ((picked!.size) > _maxAvatarBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_trStatic(context, 'avatar_too_large'))));
      }
      return;
    }

    setState(() => _uploadingAvatar = true);
    try {
      await context.read<AuthProvider>().uploadAvatar(picked.path!);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_trStatic(context, 'avatar_updated'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Widget _buildAvatar(BuildContext context, String? avatarUrl, String? displayName) {
    final url = (avatarUrl != null && avatarUrl.isNotEmpty) ? avatarUrl : null;
    final ImageProvider? image =
        url == null ? null : (url.startsWith('http') ? NetworkImage(url) : FileImage(File(url)) as ImageProvider);
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage: image,
            child: image == null ? Text(_initial(displayName)) : null,
          ),
          if (_uploadingAvatar)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            Positioned(
              right: -2,
              bottom: -2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.edit, size: 12, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
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
            leading: GestureDetector(
              onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
              child: _buildAvatar(context, auth.user?.avatarUrl, auth.user?.displayName),
            ),
            title: Text(auth.user?.displayName ?? ''),
            subtitle: Text(auth.user?.email ?? ''),
            trailing: auth.isDeveloper
                ? Chip(
                    label: Text(context.tr('developer_account'), style: const TextStyle(fontSize: 11)),
                    avatar: const Icon(Icons.verified, size: 16),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _uploadingAvatar ? null : _pickAndUploadAvatar,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(context.tr('change_avatar')),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
              ),
            ),
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
