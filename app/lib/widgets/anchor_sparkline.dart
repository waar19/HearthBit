import 'package:flutter/material.dart';

enum AnchorSparklineStyle { bars, lineArea }

class AnchorSparkline extends StatelessWidget {
  const AnchorSparkline({
    required this.series,
    required this.colors,
    required this.style,
    super.key,
  });

  final List<List<double>> series;
  final List<Color> colors;
  final AnchorSparklineStyle style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      width: double.infinity,
      child: CustomPaint(
        painter: _AnchorSparklinePainter(
          series: series,
          colors: colors,
          style: style,
          baselineColor: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _AnchorSparklinePainter extends CustomPainter {
  const _AnchorSparklinePainter({
    required this.series,
    required this.colors,
    required this.style,
    required this.baselineColor,
  });

  final List<List<double>> series;
  final List<Color> colors;
  final AnchorSparklineStyle style;
  final Color baselineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height - 1;
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()
        ..color = baselineColor
        ..strokeWidth = 1,
    );
    if (series.isEmpty || series.every((values) => values.isEmpty)) return;

    var maximum = 0.0;
    for (final values in series) {
      for (final value in values) {
        if (value > maximum) maximum = value;
      }
    }
    if (maximum <= 0) maximum = 1;

    switch (style) {
      case AnchorSparklineStyle.bars:
        _paintBars(canvas, size, maximum);
      case AnchorSparklineStyle.lineArea:
        _paintLines(canvas, size, maximum);
    }
  }

  void _paintBars(Canvas canvas, Size size, double maximum) {
    final count = series.fold<int>(
      0,
      (largest, values) => values.length > largest ? values.length : largest,
    );
    if (count == 0) return;
    final groupWidth = size.width / count;
    final barWidth = (groupWidth / (series.length + 1)).clamp(1.0, 8.0);
    for (var seriesIndex = 0; seriesIndex < series.length; seriesIndex++) {
      final values = series[seriesIndex];
      final paint = Paint()
        ..color = colors[seriesIndex % colors.length]
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;
      for (var index = 0; index < values.length; index++) {
        final x =
            groupWidth * (index + 0.5) +
            (seriesIndex - (series.length - 1) / 2) * barWidth;
        final height = values[index] / maximum * (size.height - 5);
        canvas.drawLine(
          Offset(x, size.height - 2),
          Offset(x, size.height - 2 - height),
          paint,
        );
      }
    }
  }

  void _paintLines(Canvas canvas, Size size, double maximum) {
    for (var seriesIndex = 0; seriesIndex < series.length; seriesIndex++) {
      final values = series[seriesIndex];
      if (values.isEmpty) continue;
      final color = colors[seriesIndex % colors.length];
      final path = Path();
      for (var index = 0; index < values.length; index++) {
        final x = values.length == 1
            ? size.width
            : index / (values.length - 1) * size.width;
        final y = size.height - 2 - values[index] / maximum * (size.height - 6);
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final area = Path.from(path)
        ..lineTo(size.width, size.height - 2)
        ..lineTo(0, size.height - 2)
        ..close();
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.14));
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnchorSparklinePainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.colors != colors ||
      oldDelegate.style != style ||
      oldDelegate.baselineColor != baselineColor;
}
