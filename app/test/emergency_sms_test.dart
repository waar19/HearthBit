import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/mesh_platform_service.dart';

void main() {
  group('normalizeSmsRecipient', () {
    test('conserva un número internacional y elimina separadores', () {
      expect(normalizeSmsRecipient('+56 9 1234-5678'), '+56912345678');
      expect(normalizeSmsRecipient('(212) 555 0198'), '2125550198');
    });

    test('rechaza letras, extensiones y números fuera de rango', () {
      expect(
        () => normalizeSmsRecipient('911 HELP'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => normalizeSmsRecipient('+123'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => normalizeSmsRecipient('+1234567890123456'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
