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
}
