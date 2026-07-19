/// Formats a [Duration] as "minutes:seconds" (e.g. `3:07`, `12:40`), or
/// "hours:minutes:seconds" (e.g. `1:05:32`) once it reaches an hour.
/// The leading unit is not zero-padded; the ones after it always are
/// (two digits).
String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

