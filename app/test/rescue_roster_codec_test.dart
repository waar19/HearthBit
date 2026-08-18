import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/models/rescue_roster_models.dart';
import 'package:hearth_bit/services/rescue_roster_codec.dart';

void main() {
  test('codifica HBRT1 y verifica la firma del líder', () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    const codec = RescueRosterCodec();
    final unsigned = RescueTeamRoster(
      teamId: '00112233445566778899aabbccddeeff',
      name: 'Equipo Norte',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      leaderPeerId: '0011223344556677',
      members: [
        RescueRosterMember(
          peerId: '0011223344556677',
          callsign: 'Líder 1',
          role: RescueRosterRole.leader,
          signingPublicKey: Uint8List.fromList(publicKey.bytes),
        ),
      ],
      signature: Uint8List(0),
    );
    final signed = await codec.sign(
      unsigned,
      (payload) async => Uint8List.fromList(
        (await algorithm.sign(payload, keyPair: keyPair)).bytes,
      ),
    );

    final decoded = await codec.decodeAndVerify(
      codec.encode(signed),
      verify: (peerId, key, payload, signature) async => algorithm.verify(
        payload,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
        ),
      ),
    );

    expect(decoded.name, 'Equipo Norte');
    expect(decoded.leaderPeerId, '0011223344556677');
    expect(decoded.members.single.callsign, 'Líder 1');
  });

  test('rechaza miembros duplicados antes de firmar', () {
    final key = Uint8List.fromList(List.generate(32, (index) => index + 1));
    final roster = RescueTeamRoster(
      teamId: '00112233445566778899aabbccddeeff',
      name: 'Equipo',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      leaderPeerId: '0011223344556677',
      members: [
        RescueRosterMember(
          peerId: '0011223344556677',
          callsign: 'Uno',
          role: RescueRosterRole.leader,
          signingPublicKey: key,
        ),
        RescueRosterMember(
          peerId: '0011223344556677',
          callsign: 'Dos',
          role: RescueRosterRole.medic,
          signingPublicKey: Uint8List.fromList(key.reversed.toList()),
        ),
      ],
      signature: Uint8List(64),
    );

    expect(
      () => RescueRosterCodec.canonicalPayload(roster),
      throwsFormatException,
    );
  });

  test('rechaza firma HBRT1 alterada', () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    const codec = RescueRosterCodec();
    final signed = await codec.sign(
      RescueTeamRoster(
        teamId: '00112233445566778899aabbccddeeff',
        name: 'Equipo',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        leaderPeerId: '0011223344556677',
        members: [
          RescueRosterMember(
            peerId: '0011223344556677',
            callsign: 'Uno',
            role: RescueRosterRole.leader,
            signingPublicKey: Uint8List.fromList(publicKey.bytes),
          ),
        ],
        signature: Uint8List(0),
      ),
      (payload) async => Uint8List.fromList(
        (await algorithm.sign(payload, keyPair: keyPair)).bytes,
      ),
    );
    final encoded = codec.encode(signed);
    final tampered =
        '${encoded.substring(0, encoded.length - 1)}'
        '${encoded.endsWith('A') ? 'B' : 'A'}';

    expect(
      () => codec.decodeAndVerify(
        tampered,
        verify: (peerId, key, payload, signature) async => algorithm.verify(
          payload,
          signature: Signature(
            signature,
            publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
          ),
        ),
      ),
      throwsFormatException,
    );
  });
}
