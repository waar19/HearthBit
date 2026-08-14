import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/widgets/voice_waveform.dart';

void main() {
  testWidgets('onda se adapta a poco ancho y permite buscar', (tester) async {
    double? requestedProgress;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 140,
              child: VoiceWaveform(
                samples: List.generate(32, (index) => (index + 1) / 32),
                progress: .25,
                onSeek: (value) => requestedProgress = value,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final waveform = find.byType(VoiceWaveform);
    final rect = tester.getRect(waveform);
    await tester.tapAt(Offset(rect.left + rect.width * .75, rect.center.dy));

    expect(requestedProgress, closeTo(.75, .02));
    expect(tester.takeException(), isNull);
  });
}
