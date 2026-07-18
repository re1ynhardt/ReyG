import 'package:flutter/material.dart';
import 'app.dart';
import 'services/api_service.dart';
import 'services/mock_api_service.dart';
import 'services/audio_player_service.dart';
import 'services/remote_api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initializes background playback + a full custom notification with a
  // real repeat button (requirement #9). See:
  //   lib/services/harmony_audio_handler.dart  (the AudioHandler)
  //   lib/services/audio_player_service.dart   (thin facade used by the UI)
  await AudioPlayerService.init();

  // --- Backend selection ---------- ---------------------------------------
  final ApiService api = MockApiService.instance;
  // Для локального теста на эмуляторе Android используйте:
  //   'http://10.0.2.2:8000'   (алиас localhost хост-машины для эмулятора)
  // На реальном телефоне в одной Wi-Fi сети с компьютером:
  //   'http://192.168.X.X:8000' (локальный IP компьютера)
  // -------------------------------------------------------------------

  runApp(HarmonyApp(api: api));
}
