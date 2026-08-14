import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:fftea/fftea.dart';
import 'package:record/record.dart';

class AcousticDetection {
  const AcousticDetection({
    required this.sampleIndex,
    required this.confidence,
    required this.peak,
    required this.noiseFloor,
  });

  final int sampleIndex;
  final double confidence;
  final double peak;
  final double noiseFloor;
}

class AcousticRoundObservation {
  const AcousticRoundObservation({
    required this.selfChirpSample,
    required this.remoteChirpSample,
    required this.confidence,
  });

  final int selfChirpSample;
  final int remoteChirpSample;
  final double confidence;

  int get signedDeltaSamples => remoteChirpSample - selfChirpSample;
}

class AcousticDistanceMeasurement {
  const AcousticDistanceMeasurement({
    required this.distanceMeters,
    required this.errorMeters,
    required this.confidence,
  });

  final double distanceMeters;
  final double errorMeters;
  final double confidence;
}

class AcousticSonarDsp {
  const AcousticSonarDsp._();

  static const int sampleRate = 48000;
  static const double speedOfSoundMetersPerSecond = 343;
  static const Duration chirpDuration = Duration(milliseconds: 60);
  static const double startFrequencyHz = 15500;
  static const double endFrequencyHz = 19500;
  static final int chirpSampleCount =
      (sampleRate * chirpDuration.inMicroseconds / 1000000).round();

  static Float64List generateChirp({
    int rate = sampleRate,
    Duration duration = chirpDuration,
    double startHz = startFrequencyHz,
    double endHz = endFrequencyHz,
  }) {
    final count = (rate * duration.inMicroseconds / 1000000).round();
    final output = Float64List(count);
    final seconds = duration.inMicroseconds / 1000000;
    final sweepRate = (endHz - startHz) / seconds;
    for (var index = 0; index < count; index++) {
      final time = index / rate;
      final phase =
          2 * math.pi * (startHz * time + sweepRate * time * time / 2);
      final window = 0.5 - 0.5 * math.cos(2 * math.pi * index / (count - 1));
      output[index] = math.sin(phase) * window * 0.8;
    }
    return output;
  }

  static Uint8List chirpWavBytes() {
    final chirp = generateChirp();
    final pcmBytes = chirp.length * 2;
    final output = Uint8List(44 + pcmBytes);
    final bytes = ByteData.sublistView(output);
    _writeAscii(output, 0, 'RIFF');
    bytes.setUint32(4, 36 + pcmBytes, Endian.little);
    _writeAscii(output, 8, 'WAVE');
    _writeAscii(output, 12, 'fmt ');
    bytes
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    _writeAscii(output, 36, 'data');
    bytes.setUint32(40, pcmBytes, Endian.little);
    for (var index = 0; index < chirp.length; index++) {
      bytes.setInt16(
        44 + index * 2,
        (chirp[index] * 32767).round().clamp(-32768, 32767),
        Endian.little,
      );
    }
    return output;
  }

  static Float64List decodePcm16(Iterable<Uint8List> chunks) {
    final totalBytes = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final merged = Uint8List(totalBytes);
    var offset = 0;
    for (final chunk in chunks) {
      merged.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    final alignedLength = merged.length - merged.length % 2;
    final samples = Float64List(alignedLength ~/ 2);
    final data = ByteData.sublistView(merged);
    for (var index = 0; index < samples.length; index++) {
      samples[index] = data.getInt16(index * 2, Endian.little) / 32768;
    }
    return samples;
  }

  static List<AcousticDetection> detectChirps(
    List<double> samples, {
    int maximumDetections = 2,
    double minimumConfidence = 0.35,
  }) {
    final chirp = generateChirp();
    if (samples.length < chirp.length) return const [];
    final reversed = chirp.reversed.toList(growable: false);
    final correlated = convolution(samples, reversed);
    final magnitudes = correlated.map((value) => value.abs()).toList();
    final noiseFloor = _median(magnitudes).clamp(1e-9, double.infinity);
    final exclusion = chirp.length;
    final detections = <AcousticDetection>[];
    for (var count = 0; count < maximumDetections; count++) {
      var peakIndex = -1;
      var peak = 0.0;
      for (var index = 0; index < magnitudes.length; index++) {
        final candidate = magnitudes[index];
        if (candidate > peak) {
          peak = candidate;
          peakIndex = index;
        }
      }
      if (peakIndex < 0) break;
      final ratio = peak / noiseFloor;
      final confidence = ((ratio - 3) / 17).clamp(0.0, 1.0);
      if (confidence < minimumConfidence) break;
      detections.add(
        AcousticDetection(
          sampleIndex: (peakIndex - chirp.length + 1).clamp(
            0,
            samples.length - 1,
          ),
          confidence: confidence,
          peak: peak,
          noiseFloor: noiseFloor,
        ),
      );
      final from = math.max(0, peakIndex - exclusion);
      final to = math.min(magnitudes.length, peakIndex + exclusion);
      for (var index = from; index < to; index++) {
        magnitudes[index] = 0;
      }
    }
    detections.sort(
      (first, second) => first.sampleIndex.compareTo(second.sampleIndex),
    );
    return detections;
  }

  static AcousticDistanceMeasurement? combineRound({
    required AcousticRoundObservation local,
    required AcousticRoundObservation remote,
    int rate = sampleRate,
  }) {
    final travelSamples =
        (local.signedDeltaSamples + remote.signedDeltaSamples) / 2;
    final distance = travelSamples * speedOfSoundMetersPerSecond / rate;
    if (!distance.isFinite || distance < 0 || distance > 50) return null;
    final sampleError =
        (local.signedDeltaSamples - remote.signedDeltaSamples).abs() / 2;
    return AcousticDistanceMeasurement(
      distanceMeters: distance,
      errorMeters: math.max(
        0.05,
        sampleError * speedOfSoundMetersPerSecond / rate,
      ),
      confidence: math.min(local.confidence, remote.confidence),
    );
  }

  static AcousticDistanceMeasurement? aggregate(
    Iterable<AcousticDistanceMeasurement> measurements,
  ) {
    final values = measurements.toList(growable: false);
    if (values.isEmpty) return null;
    final distances = values.map((value) => value.distanceMeters).toList()
      ..sort();
    final distance = _median(distances);
    final deviations = distances
        .map((value) => (value - distance).abs())
        .toList(growable: false);
    final measuredError = _median(deviations) * 1.4826;
    return AcousticDistanceMeasurement(
      distanceMeters: distance,
      errorMeters: math.max(
        measuredError,
        values.map((value) => value.errorMeters).reduce(math.min),
      ),
      confidence:
          values.map((value) => value.confidence).reduce((a, b) => a + b) /
          values.length,
    );
  }

  static void _writeAscii(Uint8List output, int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      output[offset + index] = value.codeUnitAt(index);
    }
  }

  static double _median(Iterable<double> values) {
    final sorted = values.toList(growable: false)..sort();
    if (sorted.isEmpty) return 0;
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}

/// Decodifica PCM16 de forma incremental en un buffer circular acotado.
///
/// Evita conservar toda la grabación y mantiene constante la memoria aun si
/// el plugin de audio continúa produciendo datos más tiempo del previsto.
class AcousticSonarStreamAnalyzer {
  static const int maximumChunkBytes = 8192;
  static const int maximumBufferedSeconds = 8;

  final Float32List _samples = Float32List(
    AcousticSonarDsp.sampleRate * maximumBufferedSeconds,
  );
  int _writeIndex = 0;
  int _sampleCount = 0;
  int _peakBufferedBytes = 0;
  int? _pendingByte;

  int get peakBufferedBytes => _peakBufferedBytes;

  void add(Uint8List bytes) {
    var offset = 0;
    while (offset < bytes.length) {
      final end = math.min(offset + maximumChunkBytes, bytes.length);
      _addBounded(bytes.sublist(offset, end));
      offset = end;
    }
  }

  void _addBounded(Uint8List bytes) {
    final merged = Uint8List(bytes.length + (_pendingByte == null ? 0 : 1));
    var targetOffset = 0;
    if (_pendingByte case final pending?) {
      merged[0] = pending;
      targetOffset = 1;
      _pendingByte = null;
    }
    merged.setRange(targetOffset, merged.length, bytes);
    var alignedLength = merged.length;
    if (alignedLength.isOdd) {
      _pendingByte = merged.last;
      alignedLength -= 1;
    }
    if (alignedLength == 0) return;
    final data = ByteData.sublistView(merged, 0, alignedLength);
    for (var offset = 0; offset < alignedLength; offset += 2) {
      _samples[_writeIndex] = data.getInt16(offset, Endian.little) / 32768;
      _writeIndex = (_writeIndex + 1) % _samples.length;
      if (_sampleCount < _samples.length) _sampleCount += 1;
    }
    _peakBufferedBytes = math.max(
      _peakBufferedBytes,
      _samples.lengthInBytes + merged.length,
    );
  }

  List<AcousticDetection> finish({int maximumDetections = 2}) {
    final ordered = Float32List(_sampleCount);
    final start = _sampleCount == _samples.length ? _writeIndex : 0;
    for (var index = 0; index < _sampleCount; index++) {
      ordered[index] = _samples[(start + index) % _samples.length];
    }
    _peakBufferedBytes = math.max(
      _peakBufferedBytes,
      _samples.lengthInBytes + ordered.lengthInBytes,
    );
    final detections = AcousticSonarDsp.detectChirps(
      ordered,
      maximumDetections: maximumDetections,
    );
    reset(clearPeak: false);
    return detections;
  }

  void reset({bool clearPeak = true}) {
    _writeIndex = 0;
    _sampleCount = 0;
    _pendingByte = null;
    if (clearPeak) _peakBufferedBytes = 0;
  }
}

class AcousticSonarCapture {
  AcousticSonarCapture({AudioRecorder? recorder, AudioPlayer? player})
    : _recorder = recorder ?? AudioRecorder(),
      _player = player ?? AudioPlayer();

  final AudioRecorder _recorder;
  final AudioPlayer _player;
  final AcousticSonarStreamAnalyzer _analyzer = AcousticSonarStreamAnalyzer();
  StreamSubscription<Uint8List>? _subscription;
  bool _capturing = false;

  bool get isCapturing => _capturing;
  int get peakBufferedBytes => _analyzer.peakBufferedBytes;

  Future<bool> start() async {
    if (_capturing) return true;
    if (!await _recorder.hasPermission()) return false;
    _analyzer.reset();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AcousticSonarDsp.sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
    _subscription = stream.listen(
      (chunk) => _analyzer.add(Uint8List.fromList(chunk)),
    );
    _capturing = true;
    return true;
  }

  Future<void> emitChirp() async {
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          isSpeakerphoneOn: true,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playAndRecord,
          options: const {
            AVAudioSessionOptions.defaultToSpeaker,
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      ),
    );
    await _player.play(
      BytesSource(AcousticSonarDsp.chirpWavBytes()),
      mode: PlayerMode.lowLatency,
    );
  }

  Future<List<AcousticDetection>> stopAndAnalyze() async {
    if (!_capturing) return const [];
    _capturing = false;
    await _recorder.stop();
    await _subscription?.cancel();
    _subscription = null;
    return _analyzer.finish();
  }

  Future<void> cancel() async {
    if (!_capturing) return;
    _capturing = false;
    await _recorder.cancel();
    await _subscription?.cancel();
    _subscription = null;
    _analyzer.reset();
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    if (_capturing) await _recorder.cancel();
    _recorder.dispose();
    await _player.dispose();
  }
}
