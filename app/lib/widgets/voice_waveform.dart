import 'dart:math' as math;

import 'package:flutter/material.dart';

class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({
    required this.samples,
    required this.progress,
    this.onSeek,
    this.height = 34,
    this.activeColor,
    this.inactiveColor,
    super.key,
  });

  final List<double> samples;
  final double progress;
  final ValueChanged<double>? onSeek;
  final double height;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final waveform = CustomPaint(
          size: Size(constraints.maxWidth, height),
          painter: _VoiceWaveformPainter(
            samples: samples.isEmpty ? fallbackVoiceWaveform() : samples,
            progress: progress.clamp(0.0, 1.0),
            activeColor: activeColor ?? colors.primary,
            inactiveColor:
                inactiveColor ?? colors.onSurfaceVariant.withValues(alpha: .35),
          ),
        );
        if (onSeek == null) return waveform;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            if (constraints.maxWidth <= 0) return;
            onSeek!(
              (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0),
            );
          },
          child: waveform,
        );
      },
    );
  }
}

List<double> fallbackVoiceWaveform({int bars = 32}) =>
    List.generate(bars, (index) {
      final wave = math.sin(index * .83).abs() * .48;
      final pulse = math.sin(index * .29 + 1.2).abs() * .32;
      return (.18 + wave + pulse).clamp(.12, 1.0);
    }, growable: false);

class _VoiceWaveformPainter extends CustomPainter {
  const _VoiceWaveformPainter({
    required this.samples,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final List<double> samples;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) return;
    const gap = 2.0;
    final barWidth = math.max(
      1.5,
      (size.width - gap * (samples.length - 1)) / samples.length,
    );
    final occupiedWidth =
        barWidth * samples.length + gap * (samples.length - 1);
    final left = math.max(0.0, (size.width - occupiedWidth) / 2);
    final playedBars = (samples.length * progress).ceil();
    final radius = Radius.circular(barWidth / 2);

    for (var index = 0; index < samples.length; index++) {
      final normalized = samples[index].clamp(.08, 1.0);
      final barHeight = math.max(4.0, normalized * size.height);
      final x = left + index * (barWidth + gap);
      final rect = Rect.fromLTWH(
        x,
        (size.height - barHeight) / 2,
        barWidth,
        barHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        Paint()..color = index < playedBars ? activeColor : inactiveColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor;
}
