import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/track.dart';

/// Where [HarmonyAudioHandler] keeps the on-the-fly streaming cache for
/// tracks that haven't been explicitly saved for offline use (see
/// [DownloadService] for that separate, user-triggered "download" cache
/// with its own UI/badges — this one is invisible, automatic, and only
/// about not re-fetching bytes over the network more than once).
///
/// Every track played via streaming is wrapped in just_audio's
/// `LockCachingAudioSource` pointed at the file this returns, so:
///  - the *first* time a track plays, its audio is streamed from Yandex
///    Storage a little at a time AND written here as it arrives;
///  - any later play of the same track — whether it's on repeat, or you
///    just come back to the same song another day — finds a complete
///    file already sitting here and just_audio serves it straight from
///    disk, no network involved at all.
class StreamCacheService {
  StreamCacheService._();

  static const _dirName = 'stream_cache';

  /// The (possibly not-yet-existing) cache file [track] should be
  /// streamed into. just_audio creates the file itself as data arrives,
  /// so callers just need the path/parent directory to exist.
  static Future<File> fileFor(Track track) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/${track.id}.${_extensionFor(track.audioUrl)}');
  }

  static String _extensionFor(String url) {
    final withoutQuery = url.split('?').first;
    final dot = withoutQuery.lastIndexOf('.');
    if (dot == -1 || dot == withoutQuery.length - 1) return 'mp3';
    final ext = withoutQuery.substring(dot + 1);
    // Guard against a runaway "extension" on a signed URL with no real one.
    return ext.length <= 5 ? ext : 'mp3';
  }
}
