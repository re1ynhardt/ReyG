import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// ---------------------------------------------------------------------
/// SETUP — required on both ends before this does anything useful:
///
/// 1. ANDROID MANIFEST (this repo's export doesn't include android/, so
///    add this yourself in android/app/src/main/AndroidManifest.xml,
///    inside the <manifest> tag, alongside the existing INTERNET
///    permission):
///
///      <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
///
///    Nothing else is needed manually — open_filex ships its own
///    FileProvider declaration that merges in automatically. Without the
///    permission above, Android still lets the *user* grant "install
///    unknown apps" for this app from a system prompt the first time you
///    try, but declaring it up front avoids that extra detour.
///
/// 2. SERVER SIDE — publish two PUBLIC-READ objects in the same bucket
///    used for everything else (e.g. under an "app/" prefix), and update
///    them on every release:
///      app/update.json   — the manifest, see [UpdateInfo.fromJson]
///      app/latest.apk    — the new build
///
///    Example update.json:
///      {
///        "buildNumber": 16,
///        "version": "1.4.0",
///        "apkUrl": "https://storage.yandexcloud.net/<bucket>/app/latest.apk",
///        "notes": "Bug fixes and performance improvements",
///        "mandatory": false
///      }
///
///    buildNumber must be the integer after the "+" in pubspec.yaml's
///    `version:` line (bump it on every release) — it's what's actually
///    compared, not the human-readable version string.
/// ---------------------------------------------------------------------

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    required this.notes,
    required this.mandatory,
  });

  final String version;
  final int buildNumber;
  final String apkUrl;
  final String notes;
  final bool mandatory;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        version: json['version'] as String? ?? '',
        buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 0,
        apkUrl: json['apkUrl'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        mandatory: json['mandatory'] as bool? ?? false,
      );
}

class UpdateService {
  UpdateService({required this.manifestUrl});

  /// Public URL of the update.json manifest described above.
  final String manifestUrl;

  /// Fetches the manifest and returns update details if the manifest's
  /// buildNumber is newer than the one this build was compiled with —
  /// null if already up to date or the manifest couldn't be read (e.g.
  /// offline; this is meant to fail quietly, especially for the silent
  /// startup check).
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final res = await http.get(Uri.parse(manifestUrl));
      if (res.statusCode != 200) return null;
      final info = UpdateInfo.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      final current = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(current.buildNumber) ?? 0;
      if (info.buildNumber <= currentBuild) return null;
      return info;
    } catch (_) {
      return null;
    }
  }

  /// Downloads [info]'s APK to a temp file, reporting 0.0–1.0 progress
  /// via [onProgress] (called with null if the server didn't send a
  /// content-length, so the caller can show an indeterminate spinner
  /// instead of a stuck progress bar). Returns the path to the
  /// downloaded file.
  Future<String> downloadUpdate(UpdateInfo info, {void Function(double? progress)? onProgress}) async {
    final request = http.Request('GET', Uri.parse(info.apkUrl));
    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      throw Exception('Update download failed (${response.statusCode})');
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/update_${info.buildNumber}.apk');
    final sink = file.openWrite();

    final total = response.contentLength;
    var received = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total != null && total > 0) {
        onProgress?.call(received / total);
      } else {
        onProgress?.call(null);
      }
    }
    await sink.close();
    return file.path;
  }

  /// Hands the downloaded APK to the system installer. On Android this
  /// shows the normal "Install app?" screen (and, the very first time,
  /// an "allow installs from this source" prompt if the manifest
  /// permission above isn't granted yet).
  Future<void> installApk(String filePath) async {
    await OpenFilex.open(filePath);
  }
}
