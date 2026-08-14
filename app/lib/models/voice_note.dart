import 'dart:math' as math;

class VoiceNoteEnvelope {
  const VoiceNoteEnvelope({
    required this.transferId,
    required this.durationSeconds,
    this.waveform = const [],
  });

  static final RegExp _pattern = RegExp(
    r'^\[HB-VOICE\|([0-9a-f]{32})\|(\d{1,3})(?:\|([0-9a-f]{8,64}))?\]$',
  );

  final String transferId;
  final int durationSeconds;
  final List<double> waveform;

  static VoiceNoteEnvelope? tryParse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) return null;
    final duration = int.tryParse(match.group(2)!);
    if (duration == null || duration < 1 || duration > 300) return null;
    final encodedWaveform = match.group(3);
    return VoiceNoteEnvelope(
      transferId: match.group(1)!,
      durationSeconds: duration,
      waveform: encodedWaveform == null
          ? const []
          : decodeWaveform(encodedWaveform),
    );
  }

  String encode() {
    final encodedWaveform = waveform.isEmpty
        ? ''
        : '|${encodeWaveform(waveform)}';
    return '[HB-VOICE|$transferId|$durationSeconds$encodedWaveform]';
  }

  static String encodeWaveform(List<double> samples, {int bars = 32}) {
    final normalized = resample(samples, bars: bars);
    return normalized
        .map(
          (sample) => (sample.clamp(0.0, 1.0) * 15).round().toRadixString(16),
        )
        .join();
  }

  static List<double> decodeWaveform(String encoded) => List.unmodifiable(
    encoded.codeUnits.map((codeUnit) {
      final value = int.tryParse(String.fromCharCode(codeUnit), radix: 16) ?? 0;
      return math.max(0.08, value / 15);
    }),
  );

  static List<double> resample(List<double> samples, {int bars = 32}) {
    if (samples.isEmpty || bars <= 0) return const [];
    return List<double>.generate(bars, (index) {
      final start = (index * samples.length / bars).floor();
      final end = math.max(
        start + 1,
        ((index + 1) * samples.length / bars).ceil(),
      );
      final bucket = samples.sublist(
        start.clamp(0, samples.length - 1),
        end.clamp(1, samples.length),
      );
      final peak = bucket.fold<double>(
        0,
        (value, item) => math.max(value, item),
      );
      return peak.clamp(0.08, 1.0);
    }, growable: false);
  }
}
