import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';

class AcousticSosModem {
  const AcousticSosModem._();

  static const int sampleRate = 48000;
  static const int symbolSamples = 384;
  static const int maximumPayloadBytes = 320;
  static const List<double> frequencies = [15500, 16500, 17500, 18500];
  static const List<int> _preamble = [
    0,
    3,
    0,
    3,
    0,
    3,
    0,
    3,
    0,
    3,
    0,
    3,
    0,
    3,
    0,
    3,
    0,
    1,
    2,
    3,
  ];

  static Duration durationForPayload(int bytes) => Duration(
    microseconds:
        (_preamble.length + (bytes + 6) * 4) *
        symbolSamples *
        Duration.microsecondsPerSecond ~/
        sampleRate,
  );

  static Float64List modulate(Uint8List payload) {
    if (payload.isEmpty || payload.length > maximumPayloadBytes) {
      throw const FormatException('Invalid acoustic SOS payload');
    }
    final framed = BytesBuilder(copy: false)
      ..add([payload.length >> 8, payload.length & 0xff])
      ..add(payload);
    final crc = _crc32(payload);
    framed.add([
      crc >> 24 & 0xff,
      crc >> 16 & 0xff,
      crc >> 8 & 0xff,
      crc & 0xff,
    ]);
    final symbols = <int>[..._preamble, ..._bytesToSymbols(framed.takeBytes())];
    final output = Float64List(symbols.length * symbolSamples);
    for (var symbolIndex = 0; symbolIndex < symbols.length; symbolIndex++) {
      final frequency = frequencies[symbols[symbolIndex]];
      for (var offset = 0; offset < symbolSamples; offset++) {
        final window = offset < 16
            ? offset / 16
            : offset >= symbolSamples - 16
            ? (symbolSamples - 1 - offset) / 16
            : 1.0;
        output[symbolIndex * symbolSamples + offset] =
            math.sin(2 * math.pi * frequency * offset / sampleRate) *
            window *
            0.72;
      }
    }
    return output;
  }

  static Uint8List wavBytes(Uint8List payload) {
    final samples = modulate(payload);
    final output = Uint8List(44 + samples.length * 2);
    final data = ByteData.sublistView(output);
    _writeAscii(output, 0, 'RIFF');
    data.setUint32(4, output.length - 8, Endian.little);
    _writeAscii(output, 8, 'WAVE');
    _writeAscii(output, 12, 'fmt ');
    data
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    _writeAscii(output, 36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var index = 0; index < samples.length; index++) {
      data.setInt16(
        44 + index * 2,
        (samples[index] * 32767).round().clamp(-32768, 32767),
        Endian.little,
      );
    }
    return output;
  }

  static Uint8List? demodulate(List<double> samples) {
    final minimumSymbols = _preamble.length + 24;
    if (samples.length < minimumSymbols * symbolSamples) return null;
    for (var phase = 0; phase < symbolSamples; phase += 64) {
      final available = (samples.length - phase) ~/ symbolSamples;
      if (available < minimumSymbols) continue;
      final symbols = List<int>.generate(
        available,
        (index) => _classify(samples, phase + index * symbolSamples),
        growable: false,
      );
      for (var start = 0; start <= symbols.length - minimumSymbols; start++) {
        if (!_matchesPreamble(symbols, start)) continue;
        final frameStart = start + _preamble.length;
        if (frameStart + 8 > symbols.length) continue;
        final lengthBytes = _symbolsToBytes(
          symbols.sublist(frameStart, frameStart + 8),
        );
        if (lengthBytes == null) continue;
        final payloadLength = lengthBytes[0] << 8 | lengthBytes[1];
        if (payloadLength < 1 || payloadLength > maximumPayloadBytes) continue;
        final frameBytes = payloadLength + 6;
        final frameSymbols = frameBytes * 4;
        if (frameStart + frameSymbols > symbols.length) continue;
        final decoded = _symbolsToBytes(
          symbols.sublist(frameStart, frameStart + frameSymbols),
        );
        if (decoded == null || decoded.length != frameBytes) continue;
        final payload = Uint8List.fromList(
          decoded.sublist(2, 2 + payloadLength),
        );
        final expectedCrc = ByteData.sublistView(
          Uint8List.fromList(decoded),
        ).getUint32(2 + payloadLength);
        if (_crc32(payload) == expectedCrc) return payload;
      }
    }
    return null;
  }

  static Float64List decodePcm16(Iterable<Uint8List> chunks) {
    final bytes = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      bytes.add(chunk);
    }
    final merged = bytes.takeBytes();
    final samples = Float64List(merged.length ~/ 2);
    final data = ByteData.sublistView(merged, 0, samples.length * 2);
    for (var index = 0; index < samples.length; index++) {
      samples[index] = data.getInt16(index * 2, Endian.little) / 32768;
    }
    return samples;
  }

  static int _classify(List<double> samples, int start) {
    var best = -1;
    var bestEnergy = 0.0;
    var secondEnergy = 0.0;
    for (var tone = 0; tone < frequencies.length; tone++) {
      var real = 0.0;
      var imaginary = 0.0;
      final frequency = frequencies[tone];
      for (var offset = 0; offset < symbolSamples; offset++) {
        final sample = samples[start + offset];
        final phase = 2 * math.pi * frequency * offset / sampleRate;
        real += sample * math.cos(phase);
        imaginary -= sample * math.sin(phase);
      }
      final energy = real * real + imaginary * imaginary;
      if (energy > bestEnergy) {
        secondEnergy = bestEnergy;
        bestEnergy = energy;
        best = tone;
      } else if (energy > secondEnergy) {
        secondEnergy = energy;
      }
    }
    if (bestEnergy < 1e-5 ||
        secondEnergy > 0 && bestEnergy / secondEnergy < 1.35) {
      return -1;
    }
    return best;
  }

  static bool _matchesPreamble(List<int> symbols, int start) {
    var errors = 0;
    for (var index = 0; index < _preamble.length; index++) {
      if (symbols[start + index] != _preamble[index] && ++errors > 2) {
        return false;
      }
    }
    return true;
  }

  static Iterable<int> _bytesToSymbols(Uint8List bytes) sync* {
    for (final byte in bytes) {
      yield byte >> 6;
      yield byte >> 4 & 0x03;
      yield byte >> 2 & 0x03;
      yield byte & 0x03;
    }
  }

  static Uint8List? _symbolsToBytes(List<int> symbols) {
    if (symbols.length % 4 != 0 || symbols.any((symbol) => symbol < 0)) {
      return null;
    }
    return Uint8List.fromList([
      for (var index = 0; index < symbols.length; index += 4)
        symbols[index] << 6 |
            symbols[index + 1] << 4 |
            symbols[index + 2] << 2 |
            symbols[index + 3],
    ]);
  }

  static int _crc32(Uint8List bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = crc & 1 == 1 ? crc >> 1 ^ 0xedb88320 : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  static void _writeAscii(Uint8List output, int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      output[offset + index] = value.codeUnitAt(index);
    }
  }
}

abstract interface class AcousticSosTransportPort {
  bool get broadcasting;
  bool get listening;

  Future<bool> startBroadcast(List<Uint8List> signedEmergencyFrames);
  Future<void> stopBroadcast();
  Future<bool> startListening(Future<void> Function(Uint8List frame) onFrame);
  Future<void> stopListening();
  Future<void> dispose();
}

class AcousticSosTransport implements AcousticSosTransportPort {
  AcousticSosTransport({AudioPlayer? player, AudioRecorder? recorder})
    : _player = player ?? AudioPlayer(),
      _recorder = recorder ?? AudioRecorder();

  static const Duration broadcastInterval = Duration(seconds: 12);
  static const Duration analysisInterval = Duration(milliseconds: 800);
  static const int maximumBufferedSeconds = 12;

  final AudioPlayer _player;
  final AudioRecorder _recorder;
  final Queue<Uint8List> _chunks = Queue();
  StreamSubscription<Uint8List>? _subscription;
  Timer? _broadcastTimer;
  Timer? _analysisTimer;
  List<Uint8List> _broadcastFrames = const [];
  int _broadcastIndex = 0;
  Future<void> Function(Uint8List frame)? _onFrame;
  int _bufferedBytes = 0;
  bool _decoding = false;
  String? _lastDetectionKey;

  @override
  bool get broadcasting => _broadcastTimer != null;
  @override
  bool get listening => _subscription != null;

  @override
  Future<bool> startBroadcast(List<Uint8List> signedEmergencyFrames) async {
    if (signedEmergencyFrames.isEmpty ||
        signedEmergencyFrames.any(
          (frame) =>
              frame.isEmpty ||
              frame.length > AcousticSosModem.maximumPayloadBytes,
        )) {
      return false;
    }
    _broadcastFrames = signedEmergencyFrames
        .map(Uint8List.fromList)
        .toList(growable: false);
    _broadcastIndex = 0;
    _broadcastTimer?.cancel();
    await _emit();
    _broadcastTimer = Timer.periodic(
      broadcastInterval,
      (_) => unawaited(_emit()),
    );
    return true;
  }

  Future<void> _emit() async {
    if (_broadcastFrames.isEmpty) return;
    final frame = _broadcastFrames[_broadcastIndex % _broadcastFrames.length];
    _broadcastIndex += 1;
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
      BytesSource(AcousticSosModem.wavBytes(frame)),
      mode: PlayerMode.lowLatency,
    );
  }

  @override
  Future<void> stopBroadcast() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _broadcastFrames = const [];
    _broadcastIndex = 0;
    await _player.stop();
  }

  @override
  Future<bool> startListening(
    Future<void> Function(Uint8List frame) onFrame,
  ) async {
    if (listening) return true;
    if (!await _recorder.hasPermission()) return false;
    _onFrame = onFrame;
    _chunks.clear();
    _bufferedBytes = 0;
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AcousticSosModem.sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
    _subscription = stream.listen(_addChunk);
    _analysisTimer = Timer.periodic(
      analysisInterval,
      (_) => unawaited(_analyze()),
    );
    return true;
  }

  void _addChunk(Uint8List chunk) {
    final copy = Uint8List.fromList(chunk);
    _chunks.addLast(copy);
    _bufferedBytes += copy.length;
    const maximumBytes =
        AcousticSosModem.sampleRate * 2 * maximumBufferedSeconds;
    while (_bufferedBytes > maximumBytes && _chunks.isNotEmpty) {
      _bufferedBytes -= _chunks.removeFirst().length;
    }
  }

  Future<void> _analyze() async {
    if (_decoding || _chunks.isEmpty) return;
    _decoding = true;
    try {
      final samples = AcousticSosModem.decodePcm16(
        _chunks.toList(growable: false),
      );
      final frame = await Isolate.run(
        () => AcousticSosModem.demodulate(samples),
      );
      if (frame == null) return;
      final key = '${frame.length}:${frame.take(12).join(',')}';
      if (key == _lastDetectionKey) return;
      _lastDetectionKey = key;
      await _onFrame?.call(frame);
    } finally {
      _decoding = false;
    }
  }

  @override
  Future<void> stopListening() async {
    _analysisTimer?.cancel();
    _analysisTimer = null;
    await _recorder.stop();
    await _subscription?.cancel();
    _subscription = null;
    _chunks.clear();
    _bufferedBytes = 0;
    _onFrame = null;
  }

  @override
  Future<void> dispose() async {
    await stopBroadcast();
    await stopListening();
    _recorder.dispose();
    await _player.dispose();
  }
}
