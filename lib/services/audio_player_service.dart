import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/track.dart';

/// Thin wrapper around [AudioPlayer] that also feeds `just_audio_background`
/// so play/pause/seek/next/prev work from the lock screen and the
/// notification shade (requirement #9), without any extra native code
/// beyond the manifest tweaks described in the README.
class AudioPlayerService {
  AudioPlayerService._internal();
  static final AudioPlayerService instance = AudioPlayerService._internal();

  final AudioPlayer player = AudioPlayer();
  List<Track> _queue = [];

  List<Track> get queue => _queue;

  Stream<Duration> get positionStream => player.positionStream;
  Stream<Duration?> get durationStream => player.durationStream;
  Stream<int?> get currentIndexStream => player.currentIndexStream;
  Stream<bool> get playingStream => player.playingStream;
  Stream<ProcessingState> get processingStateStream =>
      player.playerStateStream.map((s) => s.processingState);

  int? get currentIndex => player.currentIndex;
  bool get isPlaying => player.playing;
  Track? get currentTrack =>
      (currentIndex != null && currentIndex! >= 0 && currentIndex! < _queue.length)
          ? _queue[currentIndex!]
          : null;

  /// Loads a full queue (e.g. "all tracks", a playlist, or search results)
  /// and starts playback at [startIndex]. Each item carries a [MediaItem]
  /// tag so the OS notification / lock screen shows title, artist and
  /// cover art with working play/pause/next/prev controls.
  Future<void> loadQueueAndPlay(List<Track> tracks, {required int startIndex}) async {
    _queue = tracks;
    final source = ConcatenatingAudioSource(
      children: tracks
          .map(
            (t) => AudioSource.uri(
              Uri.parse(t.audioUrl),
              tag: MediaItem(
                id: t.id,
                title: t.title,
                artist: t.artist,
                album: t.album,
                artUri: Uri.tryParse(t.coverUrl),
                duration: t.duration,
              ),
            ),
          )
          .toList(),
    );
    await player.setAudioSource(source, initialIndex: startIndex);
    await player.play();
  }

  Future<void> playPause() async {
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> seek(Duration position) => player.seek(position);

  Future<void> next() async {
    if (player.hasNext) await player.seekToNext();
  }

  Future<void> previous() async {
    // If we're more than 3 seconds into the track, restart it instead of
    // jumping to the previous track — matches Apple Music behaviour.
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }
    if (player.hasPrevious) await player.seekToPrevious();
  }

  Future<void> stop() => player.stop();

  void dispose() => player.dispose();
}
