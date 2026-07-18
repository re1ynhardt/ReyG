import 'package:flutter/material.dart';
import 'app.dart';
import 'services/api_service.dart';
import 'services/audio_player_service.dart';
import 'services/yandex_storage_api_service.dart';
// Other backends, kept for reference (see the comment below):
// import 'services/mock_api_service.dart';
// import 'services/remote_api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initializes background playback + a full custom notification with a
  // real repeat button (requirement #9). See:
  //   lib/services/harmony_audio_handler.dart  (the AudioHandler)
  //   lib/services/audio_player_service.dart   (thin facade used by the UI)
  await AudioPlayerService.init();

  // --- Backend selection ---------------------------------------------------
  // Talks DIRECTLY to Yandex Object Storage — no separate server process,
  // no Termux, nothing to start up. The app is ready the moment it opens,
  // as long as the keys below are valid. See
  // lib/services/yandex_storage_api_service.dart for how it works and for
  // an important security note about keys embedded in the app.
  //
  // TODO: replace with your real values. Move these to a safer place
  // (e.g. --dart-define, or a secrets manager) before sharing this build.
  final ApiService api = YandexStorageApiService(
    const YandexStorageConfig(
      accessKeyId: 'YCAJE0POvQbcWw9VSrNflht9s',
      secretAccessKey: 'YCMtrMWWbFX6UB-_dO4VuNa2cAnIBZJvemoAkWic',
      bucket: 'storagereyg',
      developerEmails: {'ussr9covok@gmail.com', 'anastasiyasklyarova3091@gmail.com', 'nubik2881@gmail.com'},
    ),
  );

  // Other options, for reference:
  //   final ApiService api = MockApiService.instance; // in-memory demo data
  //   final ApiService api = RemoteApiService(baseUrl: 'http://<host>:8000'); // old VPS/Flask backend

  runApp(HarmonyApp(api: api));
}
