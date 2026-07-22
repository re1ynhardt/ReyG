import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../../models/user.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
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

  bool _uploadingAvatar = false;
  bool _uploadingBanner = false;
  bool _updatingPrivacy = false;
  bool _updatingPassword = false;
  bool _updatingBio = false;
  bool _updatingDisplayName = false;

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
    context.read<AuthProvider>().logout();
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

    if ((picked!.size) > _maxAvatarBytes) {
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
          if (auth.isDeveloper) ...[
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(context.tr('developer_account'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
          ],
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
