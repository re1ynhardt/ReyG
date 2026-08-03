import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import 'harmony_audio_handler.dart';

/// Thin facade over [HarmonyAudioHandler] that keeps the exact same public
/// API the rest of the app (PlayerProvider, screens) already relies on —
/// so switching from `just_audio_background` to a full `audio_service`
/// AudioHandler (needed for a real repeat button in the notification)
/// didn't require touching any other file.
class AudioPlayerService {
  AudioPlayerService._internal(this.handler);

  /// Set once in `main()` via [init], before `runApp()`. Every other part
  /// of the app reads the ready singleton through [instance].
  static late final AudioPlayerService instance;

  /// Initializes audio_service + our custom handler. Must be awaited in
  /// `main()` before `runApp()`.
  static Future<void> init() async {
    final handler = await AudioService.init(
      builder: () => HarmonyAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.harmony.app.audio',
        androidNotificationChannelName: 'Harmony playback',
        androidNotificationOngoing: true,
      ),
    );
    instance = AudioPlayerService._internal(handler);
  }

  final HarmonyAudioHandler handler;
  AudioPlayer get player => handler.player;

  List<Track> get queue => handler.tracks;

  Stream<Duration> get positionStream => player.positionStream;
  Stream<Duration?> get durationStream => player.durationStream;
  Stream<int?> get currentIndexStream => player.currentIndexStream;
  Stream<bool> get playingStream => player.playingStream;
  Stream<ProcessingState> get processingStateStream =>
      player.playerStateStream.map((s) => s.processingState);
  Stream<LoopMode> get loopModeStream => player.loopModeStream;

  int? get currentIndex => player.currentIndex;
  bool get isPlaying => player.playing;
  LoopMode get loopMode => player.loopMode;
  Track? get currentTrack => handler.currentTrack;

  /// Loads a full queue (e.g. "all tracks", a playlist, or search results)
  /// and starts playback at [startIndex]. Cover art, title/artist and
  /// working play/pause/next/prev/repeat all show up in the OS
  /// notification and lock screen automatically.
  Future<void> loadQueueAndPlay(List<Track> tracks, {required int startIndex}) =>
      handler.loadQueue(tracks, startIndex: startIndex);

  Future<void> playPause() async {
    if (player.playing) {
      await handler.pause();
    } else {
      await handler.play();
    }
  }

  Future<void> seek(Duration position) => handler.seek(position);

  Future<void> next() => handler.skipToNext();

  Future<void> previous() => handler.skipToPrevious();

  Future<void> stop() => handler.stop();

  Future<void> setLoopMode(LoopMode mode) => player.setLoopMode(mode);

  /// Cycles off -> repeat all -> repeat one -> off. Routed through the
  /// handler's `customAction`, which is the exact same call the system
  /// notification's repeat button makes — so tapping it in-app or in the
  /// notification shade always stays in sync.
  Future<void> cycleLoopMode() => handler.customAction('repeat');

  void dispose() => player.dispose();
}
