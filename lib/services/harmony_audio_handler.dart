import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import '../models/track.dart';
import 'download_service.dart';

/// Custom [BaseAudioHandler] wrapping just_audio's [AudioPlayer].
///
/// Unlike `just_audio_background` (which only exposes play/pause/skip in
/// the system notification), this handler adds a REAL, tappable "repeat"
/// button with its own icon straight into the Android notification shade
/// and lock screen — see [_transformState] and the `ic_repeat_*` drawables
/// referenced there (must be added under
/// `android/app/src/main/res/drawable/`, see README notes).
///
/// Tapping that notification button calls [customAction] with name
/// `'repeat'`, which is the exact same code path the in-app repeat button
/// uses (via `AudioPlayerService.cycleLoopMode`), so both stay in sync.
class HarmonyAudioHandler extends BaseAudioHandler with SeekHandler {
  HarmonyAudioHandler() {
    _init();
  }

  final AudioPlayer player = AudioPlayer();
  List<Track> _tracks = [];

  List<Track> get tracks => _tracks;

  Track? get currentTrack {
    final index = player.currentIndex;
    if (index == null || index < 0 || index >= _tracks.length) return null;
    return _tracks[index];
  }

  void _init() {
    // Recompute the full PlaybackState (and therefore the notification)
    // every time playback position/state, playing flag, or loop mode
    // changes — this is what makes the repeat icon update live.
    Rx.combineLatest3<PlaybackEvent, bool, LoopMode, PlaybackState>(
      player.playbackEventStream,
      player.playingStream,
      player.loopModeStream,
      _transformState,
    ).pipe(playbackState);

    player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _tracks.length) {
        mediaItem.add(_toMediaItem(_tracks[index]));
      }
    });
  }

  PlaybackState _transformState(PlaybackEvent event, bool playing, LoopMode loopMode) {
    // Same custom action name ('repeat') for all three icons — only the
    // icon/label changes depending on the current loop mode, exactly like
    // Spotify/YouTube Music do it.
    final repeatControl = switch (loopMode) {
      LoopMode.off => MediaControl.custom(
          androidIcon: 'drawable/ic_repeat_off',
          label: 'Repeat off',
          name: 'repeat',
        ),
      LoopMode.all => MediaControl.custom(
          androidIcon: 'drawable/ic_repeat_all',
          label: 'Repeat all',
          name: 'repeat',
        ),
      LoopMode.one => MediaControl.custom(
          androidIcon: 'drawable/ic_repeat_one',
          label: 'Repeat one',
          name: 'repeat',
        ),
    };

    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        repeatControl,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      // Android's COLLAPSED notification only fits 3 buttons. This shows
      // previous / play-pause / repeat there; "next" is still reachable
      // by expanding the notification. Swap indices if you'd rather show
      // next instead of previous, e.g. [1, 2, 3].
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[event.processingState]!,
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: event.currentIndex,
    );
  }

  MediaItem _toMediaItem(Track t) => MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        artUri: Uri.tryParse(t.coverUrl),
        duration: t.duration,
      );

  Future<void> loadQueue(List<Track> tracks, {required int startIndex}) async {
    _tracks = tracks;
    queue.add(tracks.map(_toMediaItem).toList());
    final children = await Future.wait(tracks.map(_audioSourceFor));
    final source = ConcatenatingAudioSource(children: children);
    await player.setAudioSource(source, initialIndex: startIndex);
    await play();
  }

  /// Prefers a cached on-device copy of [t] (offline playback) over
  /// streaming it, falling back to the network URL when it isn't cached.
  Future<AudioSource> _audioSourceFor(Track t) async {
    final localPath = await DownloadService.instance.cachedFilePath(t.id);
    if (localPath != null) {
      return AudioSource.uri(Uri.file(localPath), tag: t.id);
    }
    return AudioSource.uri(Uri.parse(t.audioUrl), tag: t.id);
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (player.hasNext) await player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    // Restart the current track instead of jumping back if we're more
    // than 3 seconds in — matches Apple Music behaviour.
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
      return;
    }
    if (player.hasPrevious) await player.seekToPrevious();
  }

  @override
  Future<void> stop() async {
    await player.stop();
    return super.stop();
  }

  /// Handles taps on the custom repeat button — both from the system
  /// notification AND from `AudioPlayerService.cycleLoopMode()` in-app.
  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'repeat') {
      final next = switch (player.loopMode) {
        LoopMode.off => LoopMode.all,
        LoopMode.all => LoopMode.one,
        LoopMode.one => LoopMode.off,
      };
      await player.setLoopMode(next);
    }
    return super.customAction(name, extras);
  }
}
