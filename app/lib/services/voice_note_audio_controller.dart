import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'at_rest_file_cipher.dart';

class VoiceNoteAudioController extends ChangeNotifier {
  VoiceNoteAudioController({AudioPlayer? player, AtRestFileCipher? fileCipher})
    : _player = player ?? AudioPlayer(),
      _fileCipher = fileCipher ?? AtRestFileCipher() {
    _subscriptions.add(
      _player.onPlayerStateChanged.listen((value) {
        state = value;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      _player.onPositionChanged.listen((value) {
        position = value;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      _player.onDurationChanged.listen((value) {
        duration = value;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      _player.onPlayerComplete.listen((_) {
        state = PlayerState.completed;
        position = duration;
        unawaited(_deletePlaybackTemporary());
        notifyListeners();
      }),
    );
  }

  final AudioPlayer _player;
  final AtRestFileCipher _fileCipher;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  File? _playbackTemporary;

  String? activeTransferId;
  PlayerState state = PlayerState.stopped;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  String? error;

  bool isActive(String transferId) => activeTransferId == transferId;

  bool isPlaying(String transferId) =>
      isActive(transferId) && state == PlayerState.playing;

  double progressFor(String transferId, Duration fallbackDuration) {
    if (!isActive(transferId)) return 0;
    final total = duration > Duration.zero ? duration : fallbackDuration;
    if (total <= Duration.zero) return 0;
    return (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }

  Future<void> toggle({
    required String transferId,
    required String filePath,
  }) async {
    try {
      error = null;
      if (isPlaying(transferId)) {
        await _player.pause();
        return;
      }
      await _configurePlaybackSession();
      if (isActive(transferId) && state == PlayerState.paused) {
        await _player.resume();
        return;
      }
      if (!await File(filePath).exists()) {
        throw StateError('Voice note file is not available');
      }
      await _player.stop();
      await _deletePlaybackTemporary();
      activeTransferId = transferId;
      position = Duration.zero;
      duration = Duration.zero;
      state = PlayerState.stopped;
      notifyListeners();
      final playbackFile = await _fileCipher.decryptToTemporary(File(filePath));
      if (playbackFile.path != filePath) _playbackTemporary = playbackFile;
      await _player.play(DeviceFileSource(playbackFile.path), volume: 1);
    } catch (exception) {
      error = exception.toString();
      state = PlayerState.stopped;
      notifyListeners();
    }
  }

  Future<void> seek({
    required String transferId,
    required double progress,
    required Duration fallbackDuration,
  }) async {
    if (!isActive(transferId)) return;
    final total = duration > Duration.zero ? duration : fallbackDuration;
    if (total <= Duration.zero) return;
    final target = Duration(
      milliseconds: (total.inMilliseconds * progress.clamp(0.0, 1.0)).round(),
    );
    await _player.seek(target);
  }

  Future<void> stop() async {
    await _player.stop();
    await _deletePlaybackTemporary();
    activeTransferId = null;
    state = PlayerState.stopped;
    position = Duration.zero;
    duration = Duration.zero;
    error = null;
    notifyListeners();
  }

  Future<void> resetPlaybackSession() => _configurePlaybackSession();

  Future<void> _configurePlaybackSession() async {
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          audioMode: AndroidAudioMode.normal,
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
      ),
    );
    await _player.setVolume(1);
  }

  Future<void> _deletePlaybackTemporary() async {
    final temporary = _playbackTemporary;
    _playbackTemporary = null;
    if (temporary != null && await temporary.exists()) {
      await temporary.delete();
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_deletePlaybackTemporary());
    unawaited(_player.dispose());
    super.dispose();
  }
}
