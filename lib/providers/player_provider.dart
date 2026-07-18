import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import '../models/track.dart';
import '../services/audio_player_service.dart';
import 'library_provider.dart';

class PlayerProvider extends ChangeNotifier {
  PlayerProvider(this._library) {
    _bind();
  }

  final LibraryProvider _library;
  final AudioPlayerService _service = AudioPlayerService.instance;

  Duration position = Duration.zero;
  Duration? duration;
  bool isPlaying = false;
  Track? currentTrack;
  LoopMode loopMode = LoopMode.off;

  late final List<StreamSubscription> _subs;

  void _bind() {
    _subs = [
      _service.positionStream.listen((p) {
        position = p;
        notifyListeners();
      }),
      _service.durationStream.listen((d) {
        duration = d;
        notifyListeners();
      }),
      _service.playingStream.listen((playing) {
        isPlaying = playing;
        notifyListeners();
      }),
      _service.currentIndexStream.listen((_) {
        final track = _service.currentTrack;
        currentTrack = track;
        if (track != null) {
          _library.markPlayed(track.id);
        }
        notifyListeners();
      }),
      _service.loopModeStream.listen((mode) {
        loopMode = mode;
        notifyListeners();
      }),
    ];
  }

  bool get hasTrack => currentTrack != null;
  bool get isRepeatOn => loopMode != LoopMode.off;
  bool get isRepeatOne => loopMode == LoopMode.one;

  Future<void> playQueue(List<Track> queue, {required int startIndex}) async {
    await _service.loadQueueAndPlay(queue, startIndex: startIndex);
  }

  Future<void> playSingle(Track track) => playQueue([track], startIndex: 0);

  Future<void> togglePlayPause() => _service.playPause();

  Future<void> seek(Duration position) => _service.seek(position);

  Future<void> next() => _service.next();

  Future<void> previous() => _service.previous();

  /// Cycles repeat: off -> repeat queue -> repeat current track -> off.
  Future<void> toggleRepeat() => _service.cycleLoopMode();

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
