import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_notification.dart';
import '../providers/app_state.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../theme/app_theme.dart';

/// Shows a top-anchored "notification shade" that slides down over the
/// current screen, similar to a phone's system notification drawer.
/// Call this from a bell/notifications button's `onTap`.
Future<void> showNotificationsShade(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierLabel: 'notifications',
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.35),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, _, __) => const Material(
      type: MaterialType.transparency,
      child: _NotificationsShade(),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      final blurSigma = 3 * animation.value.clamp(0.0, 1.0);
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        ),
      );
    },
  );
}

/// Short relative-time label ("now", "5m", "3h", "2d") for a notification's
/// timestamp — mirrors how most notification shades keep this compact.
String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  return '${diff.inDays}d';
}

class _NotificationsShade extends StatefulWidget {
  const _NotificationsShade();

  @override
  State<_NotificationsShade> createState() => _NotificationsShadeState();
}

class _NotificationsShadeState extends State<_NotificationsShade> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<NotificationsProvider>().load());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final notifications = context.watch<NotificationsProvider>();
    final isDeveloper = context.watch<AuthProvider>().isDeveloper;
    final count = notifications.items.length;

    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: GestureDetector(
          // Swallow taps on the panel itself so they don't fall through
          // to the barrier and close the shade.
          onTap: () {},
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.74),
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.7),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 20, offset: const Offset(0, 10)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag-handle affordance, purely decorative — echoes a
                // native system shade so the sheet reads as "pull-able".
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.hintColor.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [accent, accent.withOpacity(0.65)],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: Icon(Icons.notifications_rounded, size: 18, color: onColor(accent)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.tr('notifications'),
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, letterSpacing: -0.2),
                        ),
                      ),
                      if (count > 0)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: accent),
                          ),
                        ),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close, size: 11),
                          splashRadius: 9,
                          padding: const EdgeInsets.all(2),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Divider(height: 1, thickness: 1, color: theme.dividerColor.withOpacity(0.4)),
                ),
                Flexible(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: notifications.loading && notifications.items.isEmpty
                        ? const Padding(
                            key: ValueKey('loading'),
                            padding: EdgeInsets.fromLTRB(0, 32, 0, 44),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                          )
                        : notifications.items.isEmpty
                            ? Padding(
                                key: const ValueKey('empty'),
                                padding: const EdgeInsets.fromLTRB(28, 10, 28, 36),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 72,
                                      height: 72,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            width: 72,
                                            height: 72,
                                            decoration: BoxDecoration(
                                              color: theme.scaffoldBackgroundColor,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          Container(
                                            width: 50,
                                            height: 50,
                                            decoration: BoxDecoration(
                                              color: accent.withOpacity(0.10),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          Icon(Icons.notifications_off_rounded, size: 24, color: theme.hintColor),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      context.tr('no_notifications'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: theme.hintColor, fontSize: 14, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                key: const ValueKey('list'),
                                onRefresh: () => notifications.load(force: true),
                                color: accent,
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                                  itemCount: notifications.items.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (context, i) => _NotificationTile(
                                    key: ValueKey(notifications.items[i].id),
                                    index: i,
                                    item: notifications.items[i],
                                    deletable: isDeveloper,
                                  ),
                                ),
                              ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatefulWidget {
  const _NotificationTile({super.key, required this.item, required this.deletable, required this.index});
  final AppNotification item;
  /// True for developer accounts — enables swipe-to-delete. Deletion is
  /// still re-checked on the backend either way (see
  /// [NotificationsProvider.delete]).
  final bool deletable;
  /// Position in the list — staggers this tile's entrance animation so
  /// the list cascades in instead of popping in all at once.
  final int index;

  @override
  State<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<_NotificationTile> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _fade = curved;
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved);
    // Small per-item stagger, capped so a long list doesn't feel sluggish.
    Future.delayed(Duration(milliseconds: 25 * widget.index.clamp(0, 8)), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _askConfirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.trOnce('delete_notification_confirm_title')),
        content: Text(context.trOnce('delete_notification_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.trOnce('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.trOnce('delete')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _performDelete() async {
    if (!mounted) return;
    setState(() => _deleting = true);
    try {
      await context.read<NotificationsProvider>().delete(widget.item.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  /// Used by the trailing delete icon, where there's no dismiss
  /// animation to sequence around — confirm and delete in one go.
  Future<void> _confirmAndDelete() async {
    if (await _askConfirm()) await _performDelete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;
    final item = widget.item;

    final tile = Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, accent.withOpacity(0.7)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: accent.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Icon(Icons.campaign_rounded, size: 19, color: onColor(accent)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.25),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _relativeTime(item.createdAt),
                        style: TextStyle(fontSize: 10.5, color: theme.hintColor, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    style: TextStyle(fontSize: 12.5, color: theme.hintColor, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          if (widget.deletable) ...[
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _confirmAndDelete,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.delete_outline, size: 18, color: theme.hintColor),
              ),
            ),
          ],
        ],
      ),
    );

    final animated = RepaintBoundary(
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: tile),
      ),
    );

    if (!widget.deletable) return animated;

    if (_deleting) {
      return Stack(
        children: [
          Opacity(opacity: 0.4, child: animated),
          const Positioned.fill(
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        ],
      );
    }

    // Swipe-to-delete for developer accounts, with the same confirm
    // dialog as before. confirmDismiss only asks; a cancelled swipe
    // snaps the tile back into place. The actual removal happens in
    // onDismissed, after the swipe-away animation finishes, so we don't
    // yank the item out of the list mid-animation.
    return Dismissible(
      key: ValueKey('dismiss-${item.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _askConfirm(),
      onDismissed: (_) => _performDelete(),
      background: Container(
        margin: const EdgeInsets.only(left: 40),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.85),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
      ),
      child: animated,
    );
  }
}
