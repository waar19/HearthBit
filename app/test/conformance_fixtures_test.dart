import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/beacon_control_protocol.dart';
import 'package:hearth_bit/services/emergency_wire_codec.dart';
import 'package:hearth_bit/services/ranging_control_protocol.dart';
import 'package:hearth_bit/services/transfer_protocol.dart';

void main() {
  final fixtures = ConformanceFixtures.load();

  test('el manifiesto fija el perfil y commit upstream', () {
    expect(fixtures.schemaVersion, 1);
    expect(fixtures.upstreamCommit, '5156f7de89ec9f6a3429630d90f709b68f6fd7fd');
  });

  test('HBT decodifica la oferta y bytes firmados compartidos', () {
    final offer = TransferFrame.decode(fixtures.bytes('hbt.offer.v1'));
    expect(offer, isNotNull);
    expect(offer!.type, TransferProtocol.typeOffer);
    expect(offer.utf8Value(TransferProtocol.tagFileName), 'foto.jpg');
    expect(offer.utf8Value(TransferProtocol.tagMimeType), 'image/jpeg');
    expect(offer.u64(TransferProtocol.tagFileSize), 1048576);
    expect(offer.bytes(TransferProtocol.tagSignature), hasLength(64));
    expect(offer.signedBytes(), fixtures.bytes('hbt.offer.signed_bytes'));
  });

  test('codec Dart reconoce el flag de simulacro firmado', () {
    final bytes = fixtures.bytes('packet.v1.drill_message');
    final frame = EmergencyWireCodec.decode(bytes);
    expect(frame?.version, 1);
    expect(frame?.type, EmergencyWireCodec.messageType);
    expect(frame?.isDrill, isTrue);

    final unflagged = Uint8List.fromList(bytes)
      ..[11] = bytes[11] & ~EmergencyWireCodec.drillFlag;
    expect(EmergencyWireCodec.decode(unflagged), isNull);
    expect(
      EmergencyWireCodec.decode(
        Uint8List.fromList(bytes.sublist(0, bytes.length - 64)),
      ),
      isNull,
    );
  });

  test('HBT decodifica chunk y rechaza version o truncamiento', () {
    final chunk = TransferFrame.decode(fixtures.bytes('hbt.chunk.v1'));
    expect(chunk, isNotNull);
    expect(chunk!.type, TransferProtocol.typeDataChunk);
    expect(chunk.u32(TransferProtocol.tagChunkIndex), 3);
    expect(
      chunk.bytes(TransferProtocol.tagChunkData),
      Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]),
    );
    expect(TransferFrame.decode(fixtures.bytes('hbt.invalid.version')), isNull);
    expect(
      TransferFrame.decode(fixtures.bytes('hbt.invalid.truncated')),
      isNull,
    );
  });

  test('extensiones de emergencia comparten payloads canónicos', () {
    final beacon = BeaconControlProtocol.decode(
      fixtures.bytes('extension.beacon_control.request'),
    );
    expect(beacon?.action, BeaconControlAction.request);
    expect(beacon?.flags, BeaconControlFlags.all);

    final ranging = RangingControlProtocol.decode(
      fixtures.bytes('extension.ranging_control.request'),
    );
    expect(ranging?.action, RangingControlAction.request);
    expect(ranging?.technology, RangingTechnology.acoustic);
    expect(ranging?.round, 3);
    expect(ranging?.opaqueData, Uint8List.fromList([0xaa, 0xbb, 0xcc]));

    expect(
      fixtures.bytes('extension.emergency_capability.v1'),
      Uint8List.fromList([1, 1]),
    );
    final ack = fixtures.bytes('extension.emergency_ack.v1');
    expect(ack, hasLength(33));
    expect(ack.first, 1);
    expect(
      ack.sublist(1),
      Uint8List.fromList(List<int>.generate(32, (i) => i)),
    );
    expect(
      fixtures.bytes('extension.hbt_capability.canonical'),
      Uint8List.fromList([1]),
    );
  });

  test('legacy 0x24 se distingue por estructura exacta', () {
    expect(
      fixtures.bytes('extension.legacy_0x24.hbt_alias'),
      Uint8List.fromList([1]),
    );
    expect(
      fixtures.bytes('extension.legacy_0x24.prekey_candidate'),
      isNot(Uint8List.fromList([1])),
    );
  });
}

class ConformanceFixtures {
  ConformanceFixtures._(
    this.root,
    this.schemaVersion,
    this.upstreamCommit,
    this.paths,
  );

  final Directory root;
  final int schemaVersion;
  final String upstreamCommit;
  final Map<String, String> paths;

  static ConformanceFixtures load() {
    var directory = Directory.current.absolute;
    Directory? root;
    while (true) {
      final candidate = Directory(
        '${directory.path}${Platform.pathSeparator}tests'
        '${Platform.pathSeparator}conformance',
      );
      if (candidate.existsSync()) {
        root = candidate;
        break;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    if (root == null) {
      throw StateError('No se encontro tests/conformance');
    }
    final manifest =
        jsonDecode(
              File(
                '${root.path}${Platform.pathSeparator}fixtures.v1.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final entries = manifest['fixtures']! as List<dynamic>;
    return ConformanceFixtures._(
      root,
      manifest['schemaVersion']! as int,
      manifest['upstreamCommit']! as String,
      <String, String>{
        for (final entry in entries.cast<Map<String, dynamic>>())
          entry['id']! as String: entry['blob']! as String,
      },
    );
  }

  Uint8List bytes(String id) {
    final relative = paths[id];
    if (relative == null) throw StateError('Fixture desconocido: $id');
    final path = relative.replaceAll('/', Platform.pathSeparator);
    final hex = File(
      '${root.path}${Platform.pathSeparator}$path',
    ).readAsStringSync().replaceAll(RegExp(r'\s'), '');
    if (hex.length.isOdd) throw FormatException('Hex impar en $id');
    return Uint8List.fromList([
      for (var offset = 0; offset < hex.length; offset += 2)
        int.parse(hex.substring(offset, offset + 2), radix: 16),
    ]);
  }
}
