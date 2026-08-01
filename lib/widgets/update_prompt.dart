import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../services/update_service.dart';

/// Checks [service] for a newer build and, if one exists, walks the user
/// through downloading and installing it.
///
/// [silent] controls what happens when there's *nothing* to report:
/// - true (startup check): does and shows nothing.
/// - false (manual "Check for updates" tap): shows a snackbar confirming
///   the app is already up to date.
///
/// Safe to call after an `await` — every use of [context] here is
/// preceded by a `context.mounted` check.
Future<void> checkForUpdatesAndPrompt(
  BuildContext context, {
  required UpdateService service,
  bool silent = true,
}) async {
  final info = await service.checkForUpdate();
  if (!context.mounted) return;

  if (info == null) {
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.trOnce('up_to_date'))),
      );
    }
    return;
  }

  final shouldUpdate = await showDialog<bool>(
    context: context,
    barrierDismissible: !info.mandatory,
    builder: (dialogContext) => PopScope(
      canPop: !info.mandatory,
      child: AlertDialog(
        title: Text('${dialogContext.trOnce('update_available')} ${info.version}'),
        content: Text(
          info.notes.isEmpty ? dialogContext.trOnce('update_available_body') : info.notes,
        ),
        actions: [
          if (!info.mandatory)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.trOnce('later')),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.trOnce('update_now')),
          ),
        ],
      ),
    ),
  );

  if (shouldUpdate != true || !context.mounted) return;
  await _downloadAndInstall(context, service, info);
}

Future<void> _downloadAndInstall(BuildContext context, UpdateService service, UpdateInfo info) async {
  final progress = ValueNotifier<double?>(0);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(dialogContext.trOnce('downloading_update')),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value),
              const SizedBox(height: 12),
              Text(value == null ? '' : '${(value * 100).round()}%'),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    final path = await service.downloadUpdate(info, onProgress: (p) => progress.value = p);
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await service.installApk(path);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
