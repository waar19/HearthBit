import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/services/lan_mesh_gateway.dart';

void main() {
  test('LAN config is opt-in and rejects weak keys', () {
    const LanMeshGatewayConfig().validate();
    expect(
      () =>
          const LanMeshGatewayConfig(enabled: true, psk: [1, 2, 3]).validate(),
      throwsArgumentError,
    );
  });

  test('hello authenticates peer and negotiates maximum frame', () {
    final psk = Uint8List.fromList(List.filled(32, 7));
    final gateway = Uint8List.fromList(List.generate(16, (index) => index));
    final hello = LanGatewayFraming.buildHello(
      role: 1,
      gatewayId: gateway,
      nonce: Uint8List.fromList(List.filled(32, 9)),
      maximumFrameSize: 4096,
      psk: psk,
    );
    expect(
      hello.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      '48424c4e0101000102030405060708090a0b0c0d0e0f'
      '0909090909090909090909090909090909090909090909090909090909090909'
      '000010009c34985e1d08b27fa9e6794e0f1082310fb29d8fbb50024ca6c43c1c47fc8952',
    );

    final parsed = LanGatewayFraming.parseHello(
      hello,
      expectedRole: 1,
      psk: psk,
    );
    expect(parsed.gatewayId, gateway);
    expect(parsed.maximumFrameSize, 4096);
    expect(
      () => LanGatewayFraming.parseHello(
        hello,
        expectedRole: 1,
        psk: Uint8List.fromList(List.filled(32, 8)),
      ),
      throwsFormatException,
    );
  });

  test('message ID ignores TTL and RSR without mutating frame', () {
    final first = Uint8List.fromList(List.generate(32, (index) => index));
    final second = Uint8List.fromList(first)
      ..[2] = 99
      ..[11] ^= 0x10;

    expect(
      LanGatewayFraming.messageId(first),
      LanGatewayFraming.messageId(second),
    );
    expect(first[2], 2);
  });

  test('mDNS query requests the HearthBit service', () {
    final query = LanMdnsCodec.query();
    expect(query, containsAllInOrder('_hearthbit'.codeUnits));
    expect(query.length, greaterThan(20));
  });
}
