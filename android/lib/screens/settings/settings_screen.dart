import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../../models/user.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../providers/community_provider.dart';
import '../../providers/messages_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../services/update_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/update_prompt.dart';
import 'banner_crop_screen.dart';
import 'featured_tags_screen.dart';
import 'themes_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _maxAvatarBytes = 5 * 1024 * 1024;
  static const _maxBannerBytes = 10 * 1024 * 1024;

  bool _uploadingAvatar = false;
  bool _uploadingBanner = false;
  bool _updatingPrivacy = false;
  bool _updatingPassword = false;
  bool _updatingBio = false;
  bool _updatingDisplayName = false;
  bool _syncingRoles = false;
  bool _sendingNotification = false;
  bool _wipingMessages = false;
  bool _checkingForUpdates = false;
  bool _publishingUpdate = false;
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checkingForUpdates = true);
    try {
      await checkForUpdatesAndPrompt(
        context,
        service: context.read<UpdateService>(),
        silent: false,
      );
    } finally {
      if (mounted) setState(() => _checkingForUpdates = false);
    }
  }

  InputDecoration _passwordFieldDecoration(
    ThemeData theme, {
    required String label,
    required bool obscured,
    required VoidCallback onToggle,
  }) {
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: theme.colorScheme.primary.withOpacity(0.12)),
    );
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: theme.colorScheme.primary.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: outline,
      enabledBorder: outline,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.colorScheme.secondary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      suffixIcon: IconButton(
        splashRadius: 18,
        icon: Icon(
          obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 20,
          color: theme.colorScheme.primary.withOpacity(0.45),
        ),
        onPressed: onToggle,
      ),
    );
  }

  Future<void> _changePassword() async {
    if (_updatingPassword) return;
    final formKey = GlobalKey<FormState>();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscureNew = true;
    bool obscureConfirm = true;

    final newPassword = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.32),
      builder: (dialogContext) {
        final dTheme = Theme.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 36),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          dTheme.colorScheme.surface.withOpacity(0.72),
                          dTheme.colorScheme.surface.withOpacity(0.5),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                    ),
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dTheme.colorScheme.secondary.withOpacity(0.14),
                            ),
                            child: Icon(Icons.lock_outline, color: dTheme.colorScheme.secondary, size: 22),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            dialogContext.tr('change_password'),
                            textAlign: TextAlign.center,
                            style: dTheme.textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 22),
                          TextFormField(
                            controller: newController,
                            obscureText: obscureNew,
                            autofocus: true,
                            style: dTheme.textTheme.bodyMedium,
                            decoration: _passwordFieldDecoration(
                              dTheme,
                              label: dialogContext.tr('new_password'),
                              obscured: obscureNew,
                              onToggle: () => setDialogState(() => obscureNew = !obscureNew),
                            ),
                            validator: (v) =>
                                (v == null || v.isEmpty) ? dialogContext.tr('password_required') : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: confirmController,
                            obscureText: obscureConfirm,
                            style: dTheme.textTheme.bodyMedium,
                            decoration: _passwordFieldDecoration(
                              dTheme,
                              label: dialogContext.tr('confirm_password'),
                              obscured: obscureConfirm,
                              onToggle: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                            ),
                            validator: (v) => v != newController.text ? dialogContext.tr('password_mismatch') : null,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: dTheme.colorScheme.primary.withOpacity(0.7),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  onPressed: () => Navigator.of(dialogContext).pop(),
                                  child: Text(dialogContext.tr('cancel')),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: dTheme.colorScheme.secondary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  onPressed: () {
                                    if (formKey.currentState!.validate()) {
                                      Navigator.of(dialogContext).pop(newController.text);
                                    }
                                  },
                                  child: Text(dialogContext.tr('save')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (newPassword == null || !mounted) return;

    setState(() => _updatingPassword = true);
    try {
      await context.read<AuthProvider>().setPassword(newPassword);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_trStatic(context, 'password_updated'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _updatingPassword = false);
    }
  }

  /// Lets the user set/edit their profile description (max
  /// [AppUser.bioMaxLength] chars), shown under their avatar on their
  /// Community profile. Same frosted-glass dialog style as
  /// [_changePassword].
  Future<void> _editBio() async {
    if (_updatingBio) return;
    final controller = TextEditingController(text: context.read<AuthProvider>().user?.bio ?? '');

    final newBio = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.32),
      builder: (dialogContext) {
        final dTheme = Theme.of(dialogContext);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 36),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      dTheme.colorScheme.surface.withOpacity(0.72),
                      dTheme.colorScheme.surface.withOpacity(0.5),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dTheme.colorScheme.secondary.withOpacity(0.14),
                      ),
                      child: Icon(Icons.short_text, color: dTheme.colorScheme.secondary, size: 22),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      dialogContext.tr('bio_title'),
                      textAlign: TextAlign.center,
                      style: dTheme.textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      maxLength: AppUser.bioMaxLength,
                      style: dTheme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: dialogContext.tr('bio_hint'),
                        filled: true,
                        fillColor: dTheme.colorScheme.primary.withOpacity(0.05),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: dTheme.colorScheme.secondary, width: 1.4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: dTheme.colorScheme.primary.withOpacity(0.7),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: Text(dialogContext.tr('cancel')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: dTheme.colorScheme.secondary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
                            child: Text(dialogContext.tr('save')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (newBio == null || !mounted) return;

    setState(() => _updatingBio = true);
    try {
      await context.read<AuthProvider>().setBio(newBio);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _updatingBio = false);
    }
  }

  /// Lets the user change their display name (nickname), shown
  /// throughout the app and on their Community profile. Same
  /// frosted-glass dialog style as [_editBio] / [_changePassword].
  Future<void> _editDisplayName() async {
    if (_updatingDisplayName) return;
    final controller = TextEditingController(text: context.read<AuthProvider>().user?.displayName ?? '');
    final formKey = GlobalKey<FormState>();

    final newName = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.32),
      builder: (dialogContext) {
        final dTheme = Theme.of(dialogContext);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 36),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      dTheme.colorScheme.surface.withOpacity(0.72),
                      dTheme.colorScheme.surface.withOpacity(0.5),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dTheme.colorScheme.secondary.withOpacity(0.14),
                        ),
                        child: Icon(Icons.badge_outlined, color: dTheme.colorScheme.secondary, size: 22),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        dialogContext.tr('change_nickname'),
                        textAlign: TextAlign.center,
                        style: dTheme.textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 22),
                      TextFormField(
                        controller: controller,
                        autofocus: true,
                        maxLength: AppUser.displayNameMaxLength,
                        style: dTheme.textTheme.bodyMedium,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? dialogContext.tr('nickname_required') : null,
                        decoration: InputDecoration(
                          hintText: dialogContext.tr('nickname_hint'),
                          filled: true,
                          fillColor: dTheme.colorScheme.primary.withOpacity(0.05),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: dTheme.colorScheme.secondary, width: 1.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: dTheme.colorScheme.primary.withOpacity(0.7),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () => Navigator.of(dialogContext).pop(),
                              child: Text(dialogContext.tr('cancel')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: dTheme.colorScheme.secondary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () {
                                if (formKey.currentState?.validate() ?? false) {
                                  Navigator.of(dialogContext).pop(controller.text.trim());
                                }
                              },
                              child: Text(dialogContext.tr('save')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (newName == null || !mounted) return;

    setState(() => _updatingDisplayName = true);
    try {
      await context.read<AuthProvider>().setDisplayName(newName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _updatingDisplayName = false);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.32),
      builder: (dialogContext) {
        final dTheme = Theme.of(dialogContext);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 36),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      dTheme.colorScheme.surface.withOpacity(0.72),
                      dTheme.colorScheme.surface.withOpacity(0.5),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: dTheme.colorScheme.error.withOpacity(0.18)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dTheme.colorScheme.error.withOpacity(0.14),
                      ),
                      child: Icon(Icons.logout, color: dTheme.colorScheme.error, size: 22),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      dialogContext.tr('logout_confirm_title'),
                      textAlign: TextAlign.center,
                      style: dTheme.textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dialogContext.tr('logout_confirm_body'),
                      textAlign: TextAlign.center,
                      style: dTheme.textTheme.bodyMedium?.copyWith(color: dTheme.hintColor, fontSize: 13.5),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: dTheme.colorScheme.primary.withOpacity(0.7),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () => Navigator.of(dialogContext).pop(false),
                            child: Text(dialogContext.tr('cancel')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: dTheme.colorScheme.error,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () => Navigator.of(dialogContext).pop(true),
                            child: Text(dialogContext.tr('logout')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await context.read<AuthProvider>().logout();
    // AuthProvider swaps the base route's content to LoginScreen (see
    // SplashGate), but that only changes what's *underneath* — any
    // screens pushed on top (this Settings screen, and whatever it was
    // pushed from) stay on the Navigator stack and would otherwise keep
    // covering it. Pop back down to that base route so the login screen
    // is actually what the user sees.
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _setLikesPrivacy(String privacy) async {
    if (_updatingPrivacy) return;
    setState(() => _updatingPrivacy = true);
    try {
      await context.read<AuthProvider>().setLikesPrivacy(privacy);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _updatingPrivacy = false);
    }
  }

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

  Future<void> _syncRoles() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('sync_roles_confirm_title')),
        content: Text(context.tr('sync_roles_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('sync_roles')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _syncingRoles = true);
    try {
      final updated = await context.read<CommunityProvider>().syncAccountRoles();
      if (!mounted) return;
      final message = updated > 0
          ? context.trOnce('sync_roles_success').replaceFirst('{count}', '$updated')
          : context.trOnce('sync_roles_up_to_date');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _syncingRoles = false);
    }
  }

  /// Strictly developer-only (see the `if (auth.isDeveloper)` gate
  /// around its ListTile below). Irreversibly deletes every DM — text
  /// and chat images alike — for every user on the bucket (see
  /// [MessagesProvider.wipeAllMessages] / [YandexStorageApiService.
  /// wipeAllDirectMessages]). Guarded by a typed-confirmation dialog
  /// (not just a Cancel/Confirm choice) since this is bucket-wide and
  /// unrecoverable — there's no "just this account" version of this.
  Future<void> _wipeAllMessages() async {
    final theme = Theme.of(context);
    final confirmWord = context.tr('wipe_messages_confirm_word');
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final matches = controller.text.trim() == confirmWord;
          return AlertDialog(
            title: Text(context.tr('wipe_messages_confirm_title')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('wipe_messages_confirm_body')),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autocorrect: false,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    hintText: context.tr('wipe_messages_confirm_hint').replaceFirst('{word}', confirmWord),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(context.tr('cancel')),
              ),
              TextButton(
                onPressed: matches ? () => Navigator.of(dialogContext).pop(true) : null,
                child: Text(
                  context.tr('wipe_messages_confirm_action'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _wipingMessages = true);
    try {
      final count = await context.read<MessagesProvider>().wipeAllMessages();
      if (!mounted) return;
      final message = context.trOnce('wipe_messages_success').replaceFirst('{count}', '$count');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _wipingMessages = false);
    }
  }

  /// Developer/support (see the `if (auth.hasDeveloperRights)` gate around
  /// its ListTile below — same reach as [select_tags]). Picks a local
  /// .apk, collects the update.json fields, then uploads both through
  /// [CommunityProvider.publishAppUpdate] — see that method and
  /// [ApiService.publishAppUpdate] for exactly what gets written where.
  Future<void> _publishUpdate() async {
    if (_publishingUpdate) return;
    final formKey = GlobalKey<FormState>();
    final versionController = TextEditingController();
    final notesController = TextEditingController();
    final buildNumberController = TextEditingController();
    bool mandatory = false;
    PlatformFile? pickedApk;

    final info = _packageInfo ?? await PackageInfo.fromPlatform();
    versionController.text = info.version;
    buildNumberController.text = '${(int.tryParse(info.buildNumber) ?? 0) + 1}';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.32),
      builder: (dialogContext) {
        final dTheme = Theme.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 36),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          dTheme.colorScheme.surface.withOpacity(0.72),
                          dTheme.colorScheme.surface.withOpacity(0.5),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                    ),
                    child: Form(
                      key: formKey,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dTheme.colorScheme.secondary.withOpacity(0.14),
                              ),
                              child: Icon(Icons.system_update_alt, color: dTheme.colorScheme.secondary, size: 22),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              dialogContext.tr('publish_update'),
                              textAlign: TextAlign.center,
                              style: dTheme.textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 20),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final result = await FilePicker.platform.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['apk'],
                                );
                                final file = result?.files.single;
                                if (file?.path == null) return;
                                setDialogState(() => pickedApk = file);
                              },
                              icon: const Icon(Icons.folder_open),
                              label: Text(
                                pickedApk == null ? dialogContext.tr('publish_update_pick_apk') : pickedApk!.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: versionController,
                              decoration: InputDecoration(labelText: dialogContext.tr('publish_update_version')),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? dialogContext.tr('publish_update_version_required') : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: buildNumberController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: dialogContext.tr('publish_update_build_number')),
                              validator: (v) {
                                final n = int.tryParse(v ?? '');
                                return (n == null || n <= 0) ? dialogContext.tr('publish_update_build_number_required') : null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: notesController,
                              maxLines: 3,
                              decoration: InputDecoration(labelText: dialogContext.tr('publish_update_notes')),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: mandatory,
                              onChanged: (v) => setDialogState(() => mandatory = v),
                              title: Text(dialogContext.tr('publish_update_mandatory')),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: () => Navigator.of(dialogContext).pop(false),
                                    child: Text(dialogContext.tr('cancel')),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () {
                                      if (pickedApk == null) {
                                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                                          SnackBar(content: Text(dialogContext.tr('publish_update_pick_apk'))),
                                        );
                                        return;
                                      }
                                      if (!(formKey.currentState?.validate() ?? false)) return;
                                      Navigator.of(dialogContext).pop(true);
                                    },
                                    child: Text(dialogContext.tr('publish_update_confirm')),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || pickedApk?.path == null || !mounted) return;

    setState(() => _publishingUpdate = true);
    try {
      await context.read<CommunityProvider>().publishAppUpdate(
            localApkPath: pickedApk!.path!,
            version: versionController.text.trim(),
            buildNumber: int.parse(buildNumberController.text.trim()),
            notes: notesController.text.trim(),
            mandatory: mandatory,
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.trOnce('publish_update_success'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _publishingUpdate = false);
    }
  }

  /// Strictly developer-only (see the `if (auth.isDeveloper)` gate around
  /// its ListTile below — support/performer accounts don't get this).
  /// Same frosted-glass dialog style as [_editBio] / [_changePassword].
  Future<void> _sendNotification() async {
    if (_sendingNotification) return;
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController();
    final bodyController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.32),
      builder: (dialogContext) {
        final dTheme = Theme.of(dialogContext);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 36),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      dTheme.colorScheme.surface.withOpacity(0.72),
                      dTheme.colorScheme.surface.withOpacity(0.5),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dTheme.colorScheme.secondary.withOpacity(0.14),
                        ),
                        child: Icon(Icons.campaign_outlined, color: dTheme.colorScheme.secondary, size: 22),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        dialogContext.tr('send_notification'),
                        textAlign: TextAlign.center,
                        style: dTheme.textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 22),
                      TextFormField(
                        controller: titleController,
                        autofocus: true,
                        style: dTheme.textTheme.bodyMedium,
                        decoration: InputDecoration(
                          labelText: dialogContext.tr('notification_title_label'),
                          isDense: true,
                          filled: true,
                          fillColor: dTheme.colorScheme.primary.withOpacity(0.05),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: dTheme.colorScheme.secondary, width: 1.4),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? dialogContext.tr('notification_title_required') : null,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: bodyController,
                        maxLines: 3,
                        style: dTheme.textTheme.bodyMedium,
                        decoration: InputDecoration(
                          labelText: dialogContext.tr('notification_body_label'),
                          filled: true,
                          fillColor: dTheme.colorScheme.primary.withOpacity(0.05),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: dTheme.colorScheme.primary.withOpacity(0.12)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: dTheme.colorScheme.secondary, width: 1.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: dTheme.colorScheme.primary.withOpacity(0.7),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () => Navigator.of(dialogContext).pop(false),
                              child: Text(dialogContext.tr('cancel')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: dTheme.colorScheme.secondary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () {
                                if (formKey.currentState!.validate()) {
                                  Navigator.of(dialogContext).pop(true);
                                }
                              },
                              child: Text(dialogContext.tr('send')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (result != true || !mounted) return;

    setState(() => _sendingNotification = true);
    try {
      await context.read<NotificationsProvider>().send(
            title: titleController.text,
            body: bodyController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.trOnce('notification_sent'))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sendingNotification = false);
    }
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

  Future<void> _pickAndUploadBanner() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final picked = result?.files.single;
    if (picked?.path == null) return;

    if ((picked!.size) > _maxBannerBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_trStatic(context, 'banner_too_large'))));
      }
      return;
    }

    if (!mounted) return;
    final croppedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => BannerCropScreen(imagePath: picked.path!)),
    );
    if (croppedPath == null) return; // user backed out of the crop screen

    setState(() => _uploadingBanner = true);
    try {
      await context.read<AuthProvider>().uploadBanner(croppedPath);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_trStatic(context, 'banner_updated'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingBanner = false);
    }
  }

  Widget _buildAvatar(BuildContext context, String? avatarUrl, String? displayName) {
    final url = (avatarUrl != null && avatarUrl.isNotEmpty) ? avatarUrl : null;
    final ImageProvider? image =
        url == null ? null : (url.startsWith('http') ? CachedNetworkImageProvider(url) : FileImage(File(url)) as ImageProvider);
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
                : auth.isSupport
                    ? Chip(
                        label: Text(context.tr('support_account'), style: const TextStyle(fontSize: 11)),
                        avatar: const Icon(Icons.verified, size: 16),
                      )
                    : auth.isPerformer
                        ? Chip(
                            label: Text(context.tr('performer_account'), style: const TextStyle(fontSize: 11)),
                            avatar: const Icon(Icons.mic, size: 16),
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
          ListTile(
            leading: Icon(_uploadingBanner ? Icons.hourglass_top : Icons.image_outlined),
            title: Text(context.tr('change_banner')),
            onTap: _uploadingBanner ? null : _pickAndUploadBanner,
            trailing: _uploadingBanner
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(context.tr('change_nickname')),
            subtitle: Text(
              auth.user?.displayName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: _updatingDisplayName ? null : _editDisplayName,
            trailing: _updatingDisplayName
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(context.tr('change_password')),
            onTap: _updatingPassword ? null : _changePassword,
            trailing: _updatingPassword
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
          ),
          ListTile(
            leading: const Icon(Icons.short_text),
            title: Text(context.tr('bio_title')),
            subtitle: Text(
              (auth.user?.bio.isNotEmpty ?? false) ? auth.user!.bio : context.tr('bio_hint'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: _updatingBio ? null : _editBio,
            trailing: _updatingBio
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(context.tr('privacy_section'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              context.tr('likes_privacy_subtitle'),
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
            ),
          ),
          RadioListTile<String>(
            title: Text(context.tr('privacy_everyone')),
            subtitle: Text(context.tr('privacy_everyone_desc')),
            value: LikesPrivacy.all,
            groupValue: auth.user?.likesPrivacy ?? LikesPrivacy.all,
            onChanged: _updatingPrivacy ? null : (v) => _setLikesPrivacy(v!),
          ),
          RadioListTile<String>(
            title: Text(context.tr('privacy_favorites_only')),
            subtitle: Text(context.tr('privacy_favorites_only_desc')),
            value: LikesPrivacy.favoritesOnly,
            groupValue: auth.user?.likesPrivacy ?? LikesPrivacy.all,
            onChanged: _updatingPrivacy ? null : (v) => _setLikesPrivacy(v!),
          ),
          RadioListTile<String>(
            title: Text(context.tr('privacy_nobody')),
            subtitle: Text(context.tr('privacy_nobody_desc')),
            value: LikesPrivacy.none,
            groupValue: auth.user?.likesPrivacy ?? LikesPrivacy.all,
            onChanged: _updatingPrivacy ? null : (v) => _setLikesPrivacy(v!),
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
          ListTile(
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: appState.themeOption.swatch,
              child: Icon(
                appState.themeOption.icon,
                size: 16,
                color: appState.themeOption.isDark ? Colors.white : Colors.black87,
              ),
            ),
            title: Text(context.tr('themes_category')),
            subtitle: Text(context.tr('themes_category_subtitle')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ThemesScreen())),
          ),
          if (auth.hasDeveloperRights) ...[
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                auth.isDeveloper ? context.tr('developer_account') : context.tr('support_account'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tag, color: Colors.white),
              ),
              title: Text(context.tr('select_tags'), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(context.tr('select_tags_subtitle'), style: const TextStyle(fontSize: 12)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeaturedTagsScreen())),
            ),
            // Same reach as [select_tags] above — developer AND support
            // accounts (auth.hasDeveloperRights), so any of them can push
            // a build without needing the other release-publishing tools.
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _publishingUpdate
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.upload_file, color: Colors.white),
              ),
              title: Text(context.tr('publish_update'), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(context.tr('publish_update_subtitle'), style: const TextStyle(fontSize: 12)),
              onTap: _publishingUpdate ? null : _publishUpdate,
            ),
            // Strictly developer-only — unlike [select_tags] above, support
            // accounts do NOT get this one (see auth.isDeveloper, not
            // auth.hasDeveloperRights).
            if (auth.isDeveloper)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _syncingRoles
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.sync, color: Colors.white),
                ),
                title: Text(context.tr('sync_roles'), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(context.tr('sync_roles_subtitle'), style: const TextStyle(fontSize: 12)),
                onTap: _syncingRoles ? null : _syncRoles,
              ),
            // Strictly developer-only — same as [sync_roles] above (see
            // auth.isDeveloper, not auth.hasDeveloperRights).
            if (auth.isDeveloper)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _sendingNotification
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.campaign_outlined, color: Colors.white),
                ),
                title: Text(context.tr('send_notification'), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(context.tr('send_notification_subtitle'), style: const TextStyle(fontSize: 12)),
                onTap: _sendingNotification ? null : _sendNotification,
              ),
            // Strictly developer-only, and bucket-wide/irreversible — see
            // _wipeAllMessages' doc comment. Uses the theme's error color
            // (unlike the other developer tiles above) to visually flag
            // that this one is destructive, not just administrative.
            if (auth.isDeveloper)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _wipingMessages
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.delete_forever_outlined, color: Colors.white),
                ),
                title: Text(
                  context.tr('wipe_messages'),
                  style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.error),
                ),
                subtitle: Text(context.tr('wipe_messages_subtitle'), style: const TextStyle(fontSize: 12)),
                onTap: _wipingMessages ? null : _wipeAllMessages,
              ),
          ],
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(context.tr('about'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(context.tr('app_version')),
            subtitle: Text(
              _packageInfo == null ? '' : '${_packageInfo!.version} (${_packageInfo!.buildNumber})',
            ),
          ),
          ListTile(
            leading: _checkingForUpdates
                ? const SizedBox(width: 24, height: 24, child: Padding(
                    padding: EdgeInsets.all(2),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ))
                : const Icon(Icons.system_update_alt),
            title: Text(context.tr('check_for_updates')),
            subtitle: _checkingForUpdates ? Text(context.tr('checking_for_updates')) : null,
            onTap: _checkingForUpdates ? null : _checkForUpdates,
          ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(context.tr('logout'), style: const TextStyle(color: Colors.red)),
            onTap: _confirmLogout,
          ),
        ],
      ),
    );
  }
}
