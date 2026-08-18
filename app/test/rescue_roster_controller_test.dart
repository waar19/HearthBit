import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/controllers/rescue_roster_controller.dart';
import 'package:hearth_bit/models/rescue_roster_models.dart';
import 'package:hearth_bit/services/mesh_platform_service.dart';
import 'package:hearth_bit/services/rescue_roster_repository.dart';

class _Platform extends MeshPlatformService {
  _Platform(this.algorithm, this.keyPair);

  final Ed25519 algorithm;
  final SimpleKeyPair keyPair;
  final List<List<RescueRosterMember>> importedPins = [];

  @override
  Future<Uint8List> signPayload(Uint8List data) async =>
      Uint8List.fromList((await algorithm.sign(data, keyPair: keyPair)).bytes);

  @override
  Future<bool> verifySignatureWithPublicKey({
    required Uint8List signingPublicKey,
    required Uint8List data,
    required Uint8List signature,
  }) => algorithm.verify(
    data,
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(signingPublicKey, type: KeyPairType.ed25519),
    ),
  );

  @override
  Future<void> importRescueRosterPins(
    Iterable<RescueRosterMember> members,
  ) async {
    importedPins.add(members.toList(growable: false));
  }
}

class _Repository extends RescueRosterRepository {
  RescueTeamRoster? stored;

  @override
  Future<RescueTeamRoster?> loadActiveRoster() async => stored;

  @override
  Future<void> saveActiveRoster(RescueTeamRoster roster) async {
    stored = roster;
  }

  @override
  Future<void> clear() async {
    stored = null;
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('crea, exporta e importa roster y exige ID más clave', () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final platform = _Platform(algorithm, keyPair);
    final mesh = MeshController(platform: platform)
      ..peerId = '0011223344556677'
      ..nickname = 'Ana'
      ..signingPublicKey = Uint8List.fromList(publicKey.bytes);
    final repository = _Repository();
    final controller = RescueRosterController(
      mesh: mesh,
      platform: platform,
      repository: repository,
    );

    await controller.initialize();
    final created = await controller.createRoster(
      teamName: 'Equipo Norte',
      leaderCallsign: 'Norte 1',
    );
    final exported = controller.exportRoster();
    expect(exported, startsWith('HBRT1:'));
    expect(platform.importedPins.last.single.peerId, mesh.peerId);
    expect(
      controller.verifiedMember(
        peerId: mesh.peerId,
        signingPublicKey: mesh.signingPublicKey,
      ),
      same(created.members.single),
    );
    expect(
      controller.verifiedMember(
        peerId: '8899aabbccddeeff',
        signingPublicKey: mesh.signingPublicKey,
      ),
      isNull,
    );
    final responderKey = Uint8List.fromList(
      List.generate(32, (index) => index + 1),
    );
    await controller.addMember(
      peerId: '8899aabbccddeeff',
      callsign: 'Norte 2',
      role: RescueRosterRole.medic,
      signingPublicKey: responderKey,
    );
    expect(controller.members, hasLength(2));
    expect(
      controller
          .verifiedMember(
            peerId: '8899aabbccddeeff',
            signingPublicKey: responderKey,
          )
          ?.role,
      RescueRosterRole.medic,
    );
    await controller.removeMember('8899aabbccddeeff');
    expect(controller.members, hasLength(1));

    await controller.clearRoster();
    await controller.importRoster(exported);
    expect(controller.activeRoster?.name, 'Equipo Norte');

    controller.dispose();
    mesh.dispose();
  });
}
