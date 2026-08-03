import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
import '../providers/app_state.dart';

/// A short, feed-style relative timestamp for [dt] — "сейчас"/"now",
/// "5 мин"/"5m", "3 ч"/"3h", "2 дн"/"2d" — falling back to a plain
/// `dd.mm` (or `dd.mm.yyyy` once it's not this year) past a week old.
/// Localized the same way [L10nX.tr] is; call this from `build` (or
/// anywhere else that's safe to listen to [AppState] from).
String formatRelativeTime(BuildContext context, DateTime dt) {
  final isRu = Provider.of<AppState>(context, listen: true).locale == AppStrings.ru;
  final diff = DateTime.now().difference(dt);

  if (diff.inSeconds < 60) return isRu ? 'сейчас' : 'now';
  if (diff.inMinutes < 60) return isRu ? '${diff.inMinutes} мин' : '${diff.inMinutes}m';
  if (diff.inHours < 24) return isRu ? '${diff.inHours} ч' : '${diff.inHours}h';
  if (diff.inDays < 7) return isRu ? '${diff.inDays} дн' : '${diff.inDays}d';

  final sameYear = dt.year == DateTime.now().year;
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  return sameYear ? '$day.$month' : '$day.$month.${dt.year}';
}

/// Full absolute date as `dd.mm.yyyy` — always includes the year,
/// unlike [formatRelativeTime]'s same-year shorthand.
String formatAbsoluteDate(DateTime dt) {
  final day = dt.day.toString().padLeft(2, '0');
  final month = dt.month.toString().padLeft(2, '0');
  return '$day.$month.${dt.year}';
}
