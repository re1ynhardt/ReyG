import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

/// Handles caching track audio files (and their cover art) on-device so
/// they can be played back — and browsed — without a network connection.
/// Mirrors [CacheService]'s SharedPreferences-backed list pattern (see
/// `cached_track_ids`), but is a [ChangeNotifier] on top of that so
/// screens can react live to caching starting/finishing/progressing
/// (spinners, "cached" badges, etc.).
class DownloadService extends ChangeNotifier {
  DownloadService._internal() {
    _restore();
  }
  static final DownloadService instance = DownloadService._internal();

  static const _kCachedIds = 'cached_track_ids';
  static const _kCoverFiles = 'cached_cover_files';
  static const _kCacheDirName = 'cached_tracks';

  // Newest-cached-first, same convention as recently played.
  List<String> _cachedIds = [];
  // trackId -> cover filename (not the audio file, which is looked up by
  // scanning the dir — see [cachedFilePath]). Kept in memory + persisted
  // so [coverPathFor] can stay synchronous for widgets to use in build().
  Map<String, String> _coverFiles = {};
  final Map<String, double> _progress = {};
  Directory? _cacheDir;

  List<String> get cachedTrackIds => List.unmodifiable(_cachedIds);
  bool isCached(String trackId) => _cachedIds.contains(trackId);

  /// Null when the track isn't currently being cached; 0.0-1.0 (or -1 for
  /// an indeterminate download, e.g. no content-length header) otherwise.
  double? progressFor(String trackId) => _progress[trackId];
  bool isCaching(String trackId) => _progress.containsKey(trackId);

  /// Synchronous — the on-device path of [trackId]'s cover if it was
  /// cached alongside its audio, or null. Safe to call from build().
  String? coverPathFor(String trackId) {
    final dir = _cacheDir;
    final filename = _coverFiles[trackId];
    if (dir == null || filename == null) return null;
    return '${dir.path}/$filename';
  }

  Future<void> _restore() async {
    // Resolved up-front (not lazily on first cacheTrack call) so
    // [coverPathFor] has a directory to build paths from as soon as the
    // cached-ids/cover-files maps below are loaded.
    await _dir();
    final prefs = await SharedPreferences.getInstance();
    final rawIds = prefs.getString(_kCachedIds);
    if (rawIds != null) {
      _cachedIds = (jsonDecode(rawIds) as List).map((e) => e as String).toList();
    }
    final rawCovers = prefs.getString(_kCoverFiles);
    if (rawCovers != null) {
      _coverFiles = (jsonDecode(rawCovers) as Map).map((k, v) => MapEntry(k as String, v as String));
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCachedIds, jsonEncode(_cachedIds));
    await prefs.setString(_kCoverFiles, jsonEncode(_coverFiles));
  }

  Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_kCacheDirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  String _extensionFor(String url, {String fallback = 'mp3'}) {
    final withoutQuery = url.split('?').first;
    final dot = withoutQuery.lastIndexOf('.');
    if (dot == -1 || dot == withoutQuery.length - 1) return fallback;
    final ext = withoutQuery.substring(dot + 1);
    // Guard against a runaway "extension" when the URL has no real one
    // (e.g. a signed URL whose last path segment has no dot but does have
    // other punctuation before the query string).
    return ext.length <= 5 ? ext : fallback;
  }

  Future<File> _fileFor(Track track) async {
    final dir = await _dir();
    return File('${dir.path}/${track.id}.${_extensionFor(track.audioUrl)}');
  }

  /// Returns the local file path for [trackId] if it's cached and the file
  /// still exists on disk, or null otherwise. Used by playback to prefer
  /// the on-device copy over streaming.
  Future<String?> cachedFilePath(String trackId) async {
    if (!isCached(trackId)) return null;
    final dir = await _dir();
    // Extension isn't known without the Track, so look for any file that
    // starts with the id (but not its cover) — there's only ever one
    // audio file per track.
    final matches = await dir
        .list()
        .where((e) =>
            e is File &&
            e.uri.pathSegments.last.startsWith('$trackId.') &&
            !e.uri.pathSegments.last.contains('_cover.'))
        .toList();
    if (matches.isEmpty) return null;
    return matches.first.path;
  }

  /// Best-effort cover download — failures here don't affect the audio
  /// cache, since the track is still fully playable offline without it.
  Future<void> _cacheCover(Track track) async {
    if (track.coverUrl.isEmpty) return;
    try {
      final dir = await _dir();
      final filename = '${track.id}_cover.${_extensionFor(track.coverUrl, fallback: 'jpg')}';
      final response = await http.get(Uri.parse(track.coverUrl));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      await File('${dir.path}/$filename').writeAsBytes(response.bodyBytes);
      _coverFiles[track.id] = filename;
    } catch (_) {
      // Ignore — the small cover thumbnail will just keep loading from
      // the network for this track.
    }
  }

  /// Downloads [track]'s audio (and, best-effort, its cover art) to
  /// on-device storage. Safe to call again while already cached (no-op)
  /// or already in progress (no-op — the existing download continues).
  Future<void> cacheTrack(Track track) async {
    if (isCached(track.id) || isCaching(track.id)) return;

    _progress[track.id] = 0;
    notifyListeners();

    try {
      final file = await _fileFor(track);
      final request = http.Request('GET', Uri.parse(track.audioUrl));
      final response = await http.Client().send(request);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Download failed (${response.statusCode})');
      }

      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        _progress[track.id] = total != null && total > 0 ? received / total : -1;
        notifyListeners();
      }
      await sink.close();

      await _cacheCover(track);

      _cachedIds.remove(track.id);
      _cachedIds.insert(0, track.id);
      await _persist();
    } finally {
      _progress.remove(track.id);
      notifyListeners();
    }
  }

  /// Removes a cached track's audio file and cover (if any) and drops it
  /// from the cached list.
  Future<void> removeCachedTrack(String trackId) async {
    final path = await cachedFilePath(trackId);
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    final coverPath = coverPathFor(trackId);
    if (coverPath != null) {
      final coverFile = File(coverPath);
      if (await coverFile.exists()) await coverFile.delete();
    }
    _cachedIds.remove(trackId);
    _coverFiles.remove(trackId);
    await _persist();
    notifyListeners();
  }
}
