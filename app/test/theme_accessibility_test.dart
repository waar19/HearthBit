import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/main.dart';

void main() {
  test('alto contraste escala solo estilos con tamaño definido', () {
    const source = TextTheme(
      bodyLarge: TextStyle(fontSize: 16),
      bodyMedium: TextStyle(fontWeight: FontWeight.bold),
    );

    final scaled = scaleDefinedTextTheme(source, 1.12);

    expect(scaled.bodyLarge?.fontSize, closeTo(17.92, 0.001));
    expect(scaled.bodyMedium?.fontSize, isNull);
    expect(scaled.bodyMedium?.fontWeight, FontWeight.bold);
  });

  testWidgets(
    'alterna alto contraste sin fallar al interpolar el texto del botón',
    (tester) async {
      Widget app({required bool highContrast}) {
        return MaterialApp(
          theme: buildAppTheme(
            Brightness.light,
            amoled: false,
            highContrast: highContrast,
          ),
          home: const Scaffold(
            body: Center(
              child: FilledButton(onPressed: null, child: Text('Activar')),
            ),
          ),
        );
      }

      await tester.pumpWidget(app(highContrast: false));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(app(highContrast: true));
      await tester.pump(kThemeChangeDuration ~/ 2);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();

      await tester.pumpWidget(app(highContrast: false));
      await tester.pump(kThemeChangeDuration ~/ 2);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
