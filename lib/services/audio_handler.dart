import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../constants/app_info.dart';
import '../models/document.dart';
import 'repository.dart';

const skipInterval = Duration(seconds: 10);

/// Background playback: notification, lock screen and media buttons all
/// route here. just_audio handles audio focus (pauses on calls, resumes
/// after transient losses) and pauses when headphones are unplugged.
class PlayerAudioHandler extends BaseAudioHandler with SeekHandler {
  PlayerAudioHandler(this._repo) {
    _ready = _init();
  }

  final DocumentRepository _repo;
  final AudioPlayer _player = AudioPlayer();
  late final Future<void> _ready;
  String? _docId;
  Timer? _saveTimer;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<double> get speedStream => _player.speedStream;
  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;
  bool get playing => _player.playing;
  double get speed => _player.speed;
  String? get currentDocumentId => _docId;

  Future<void> _init() async {
    final session = await AudioSession.instance;
    // Spoken audio: pause rather than duck when another app talks.
    await session.configure(const AudioSessionConfiguration.speech());
    _player.playbackEventStream.listen((_) => _broadcastState(),
        onError: (Object _) => _broadcastState());
    _player.speedStream.listen((_) => _broadcastState());
    _player.playingStream.listen((playing) {
      _saveTimer?.cancel();
      if (playing) {
        _saveTimer =
            Timer.periodic(const Duration(seconds: 5), (_) => savePosition());
      } else {
        savePosition();
      }
    });
    _player.processingStateStream.listen((state) async {
      if (state == ProcessingState.completed) {
        await _player.pause();
        await savePosition();
      }
    });
  }

  /// Loads a document's audio, resuming at its saved position. No-op if it
  /// is already loaded.
  Future<void> openDocument(Document doc, {double? speed}) async {
    await _ready;
    if (_docId == doc.id) return;
    if (_docId != null) {
      await savePosition();
      await _player.stop();
    }
    _docId = doc.id;
    final total = doc.totalDuration ?? Duration.zero;
    // Finished books start again from the top.
    final start = doc.lastPosition >= total - const Duration(seconds: 2)
        ? Duration.zero
        : doc.lastPosition;
    final loaded = await _player.setFilePath(doc.audioPath!, initialPosition: start);
    if (speed != null) await _player.setSpeed(speed);
    mediaItem.add(MediaItem(
      id: doc.id,
      title: doc.title,
      album: kAppName,
      duration: loaded ?? doc.totalDuration,
    ));
  }

  /// Stops and unloads [id] if it is playing, e.g. before deleting its audio.
  Future<void> closeIfCurrent(String id) async {
    if (_docId != id) return;
    _saveTimer?.cancel();
    _docId = null;
    await _player.stop();
    mediaItem.add(null);
  }

  Future<void> savePosition() async {
    final id = _docId;
    if (id == null || _player.duration == null) return;
    await _repo.savePosition(id, _player.position);
  }

  Future<void> seekBy(Duration delta) => seek(_player.position + delta);

  @override
  Future<void> seek(Duration position) async {
    final max = duration;
    final clamped = position < Duration.zero
        ? Duration.zero
        : (position > max ? max : position);
    await _player.seek(clamped);
    if (!_player.playing) await savePosition();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> fastForward() => seekBy(skipInterval);

  @override
  Future<void> rewind() => seekBy(-skipInterval);

  // Headphone / Bluetooth next and previous buttons skip within the book.
  @override
  Future<void> skipToNext() => seekBy(skipInterval);

  @override
  Future<void> skipToPrevious() => seekBy(-skipInterval);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> stop() async {
    await savePosition();
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() => stop();

  void _broadcastState() {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.rewind,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    ));
  }
}
