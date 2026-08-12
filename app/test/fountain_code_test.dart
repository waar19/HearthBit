import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/fountain_code.dart';
import 'package:hearth_bit/services/optical_protocol.dart';

Uint8List _randomData(int length, int seed) {
  final random = Random(seed);
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

void main() {
  test('emisor y receptor derivan los mismos vecinos por símbolo', () {
    final soliton = RobustSoliton(40);
    for (var index = 0; index < 200; index++) {
      final a = symbolNeighbors(
        seed: 1234,
        symbolIndex: index,
        chunkCount: 40,
        soliton: soliton,
      );
      final b = symbolNeighbors(
        seed: 1234,
        symbolIndex: index,
        chunkCount: 40,
        soliton: RobustSoliton(40),
      );
      expect(a, b);
      expect(a.toSet().length, a.length);
    }
  });

  test('reconstruye el archivo con pérdida de frames del 35 %', () {
    final data = _randomData(10240, 7);
    final encoder = FountainEncoder(data: data, chunkSize: 128, seed: 99);
    final decoder = FountainDecoder(
      chunkCount: encoder.chunkCount,
      chunkSize: 128,
      seed: 99,
    );
    final loss = Random(21);
    var index = 0;
    while (!decoder.isComplete) {
      expect(index, lessThan(5000), reason: 'el decodificador no converge');
      final symbol = encoder.encodeSymbol(index);
      if (loss.nextDouble() > 0.35) {
        decoder.addSymbol(index, symbol);
      }
      index += 1;
    }
    expect(decoder.assemble(data.length), data);
  });

  test('los símbolos duplicados no rompen ni cuentan dos veces', () {
    final data = _randomData(1000, 3);
    final encoder = FountainEncoder(data: data, chunkSize: 100, seed: 5);
    final decoder = FountainDecoder(
      chunkCount: encoder.chunkCount,
      chunkSize: 100,
      seed: 5,
    );
    for (var round = 0; round < 3; round++) {
      for (var index = 0; index < 40 && !decoder.isComplete; index++) {
        decoder.addSymbol(index, encoder.encodeSymbol(index));
      }
    }
    expect(decoder.isComplete, isTrue);
    expect(decoder.assemble(data.length), data);
  });

  test('un archivo de un solo chunk se decodifica con el primer símbolo', () {
    final data = _randomData(50, 11);
    final encoder = FountainEncoder(data: data, chunkSize: 128, seed: 1);
    final decoder = FountainDecoder(chunkCount: 1, chunkSize: 128, seed: 1);
    decoder.addSymbol(0, encoder.encodeSymbol(0));
    expect(decoder.isComplete, isTrue);
    expect(decoder.assemble(data.length), data);
  });

  group('protocolo óptico HBQ', () {
    test('la cabecera sobrevive al viaje de ida y vuelta', () {
      final header = OpticalHeader(
        transferId: Uint8List.fromList(List.generate(16, (i) => i)),
        seed: 0xdeadbeef,
        fileSize: 123456789,
        chunkSize: 420,
        chunkCount: 294,
        sha256: Uint8List.fromList(List.generate(32, (i) => 255 - i)),
        fileName: 'reporte fotográfico.jpg',
        senderPeerId: 'a1b2c3d4e5f60718',
      );
      final decoded = OpticalProtocol.decode(
        OpticalProtocol.encodeHeader(header),
      );
      expect(decoded, isA<OpticalHeader>());
      final result = decoded! as OpticalHeader;
      expect(result.transferId, header.transferId);
      expect(result.seed, header.seed);
      expect(result.fileSize, header.fileSize);
      expect(result.chunkSize, header.chunkSize);
      expect(result.chunkCount, header.chunkCount);
      expect(result.sha256, header.sha256);
      expect(result.fileName, header.fileName);
      expect(result.senderPeerId, header.senderPeerId);
    });

    test('el símbolo de datos sobrevive al viaje de ida y vuelta', () {
      final id = Uint8List.fromList(List.generate(16, (i) => i * 3));
      final payload = _randomData(420, 13);
      final decoded = OpticalProtocol.decode(
        OpticalProtocol.encodeData(
          transferId: id,
          symbolIndex: 70000,
          payload: payload,
        ),
      );
      expect(decoded, isA<OpticalDataSymbol>());
      final result = decoded! as OpticalDataSymbol;
      expect(result.transferId, id);
      expect(result.symbolIndex, 70000);
      expect(result.payload, payload);
    });

    test('rechaza contenido ajeno sin lanzar excepciones', () {
      expect(OpticalProtocol.decode('https://example.com'), isNull);
      expect(OpticalProtocol.decode('SEJRAQ=='), isNull);
      expect(OpticalProtocol.decode(''), isNull);
    });
  });
}
