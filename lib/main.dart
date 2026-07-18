import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'app.dart';
import 'services/api_service.dart';
import 'services/mock_api_service.dart';
// To use the real backend instead, uncomment:
// import 'services/remote_api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enables lock-screen / notification-shade playback controls
  // (play/pause/next/prev + cover art) — requirement #9.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.harmony.app.audio',
    androidNotificationChannelName: 'Harmony playback',
    androidNotificationOngoing: true,
  );

  // --- Backend selection -------------------------------------------------
  // Today: fully working mock/in-memory backend, zero setup required.
  final ApiService api = MockApiService.instance;

  // Later, once the Python backend is deployed, switch to:
  //   final ApiService api = RemoteApiService(baseUrl: 'https://your-server.com');
  // Every screen already talks only to the ApiService interface, so this
  // one-line change is the entire integration.
  // -------------------------------------------------------------------

  runApp(HarmonyApp(api: api));
}
