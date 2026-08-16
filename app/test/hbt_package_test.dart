import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/hbt_package.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hbt-package-test-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('HBTX conserva transferId y contenedor sin alterarlos', () async {
    final container = File('${directory.path}/source.enc');
    final payload = Uint8List.fromList(List.generate(1024, (i) => i & 0xff));
    await container.writeAsBytes(payload);
    final transferId = Uint8List.fromList(List.generate(16, (i) => i));
    final package = File('${directory.path}/transfer.hbt');

    await HbtPackageProtocol.writeExchange(
      container: container,
      transferId: transferId,
      destination: package,
    );
    final header = await HbtPackageProtocol.inspect(package);
    final extracted = File('${directory.path}/extracted.enc');
    await HbtPackageProtocol.extractExchange(
      package: package,
      header: header,
      destination: extracted,
    );

    expect(header.kind, HbtPackageKind.exchange);
    expect(header.transferId, transferId);
    expect(await extracted.readAsBytes(), payload);
  });

  test('HBTX rechaza cabecera alterada o longitud incoherente', () async {
    final broken = File('${directory.path}/broken.hbt');
    await broken.writeAsBytes([
      ...'HBTX'.codeUnits,
      HbtPackageProtocol.version,
      ...List.filled(16, 0),
      ...List.filled(8, 0),
    ]);

    expect(
      () => HbtPackageProtocol.inspect(broken),
      throwsA(isA<FormatException>()),
    );
  });
}
