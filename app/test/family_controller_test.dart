import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hearth_bit/controllers/family_controller.dart';
import 'package:hearth_bit/controllers/mesh_controller.dart';
import 'package:hearth_bit/models/family_models.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/services/family_notification_service.dart';
import 'package:hearth_bit/services/family_repository.dart';
import 'package:hearth_bit/services/mesh_platform_service.dart';
import 'package:hearth_bit/services/message_repository.dart';

class _Platform extends MeshPlatformService {
  final eventsController = StreamController<Map<Object?, Object?>>.broadcast();

  @override
  Stream<Map<Object?, Object?>> get events => eventsController.stream;

  @override
  Future<Map<Object?, Object?>> getCapabilities() async => const {};

  @override
  Future<Map<Object?, Object?>> getPowerStatus() async => const {};
}

class _Messages extends MessageRepository {
  @override
  Future<List<MeshMessage>> load() async => const [];

  @override
  Future<List<MeshPeer>> loadKnownPeers() async => const [];

  @override
  Future<List<PendingPrivateMessage>> listPendingPrivateMessages() async =>
      const [];

  @override
  Future<void> save(MeshMessage message) async {}

  @override
  Future<void> saveKnownPeers(Iterable<MeshPeer> peers) async {}
}

class _Families extends FamilyRepository {
  _Families(this.storedMembers);

  final List<FamilyMember> storedMembers;
  Uint8List? ownerKey;
  int clearTrustCalls = 0;

  @override
  Future<List<FamilyGroup>> listGroups() async => const [];

  @override
  Future<List<FamilyMember>> listMembers({int? groupId}) async => storedMembers;

  @override
  Future<Uint8List?> readOwnerSigningKey() async => ownerKey;

  @override
  Future<void> bindOwnerSigningKey(Uint8List signingPublicKey) async {
    ownerKey = Uint8List.fromList(signingPublicKey);
  }

  @override
  Future<void> clearTrust() async {
    clearTrustCalls += 1;
    ownerKey = null;
    storedMembers.clear();
  }

  @override
  Future<void> close() async {}
}

class _Notifications implements FamilyNotificationSink {
  final List<String> messageIds = [];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> show({
    required String messageId,
    required String nickname,
    required String status,
  }) async {
    messageIds.add(messageId);
  }
}

void main() {
  final key = Uint8List.fromList(List.generate(32, (index) => index));
  final member = FamilyMember(
    id: 1,
    groupId: 1,
    peerId: '0011223344556677',
    nickname: 'Ana',
    signingPublicKey: key,
    fingerprint: '00:11:22:33:44:55',
    verifiedAt: DateTime.fromMillisecondsSinceEpoch(1000),
  );

  test('clasifica por clave Ed25519 verificada y no solo por peerId', () {
    final matchingPeer = MeshPeer(
      id: '8899aabbccddeeff',
      nickname: 'Nombre cambiado',
      lastSeen: DateTime.now(),
      secure: false,
      signingPublicKey: Uint8List.fromList(key),
    );

    expect(
      FamilyTrustClassifier.verifiedMember(
        peerId: matchingPeer.id,
        onlinePeers: [matchingPeer],
        members: [member],
      ),
      same(member),
    );
  });

  test('rechaza peer histórico offline y cambio de identidad', () {
    expect(
      FamilyTrustClassifier.verifiedMember(
        peerId: member.peerId,
        onlinePeers: const [],
        members: [member],
      ),
      isNull,
    );
    final changedIdentity = MeshPeer(
      id: member.peerId,
      nickname: member.nickname,
      lastSeen: DateTime.now(),
      secure: true,
      signingPublicKey: Uint8List.fromList(List.filled(32, 9)),
    );
    expect(
      FamilyTrustClassifier.verifiedMember(
        peerId: member.peerId,
        onlinePeers: [changedIdentity],
        members: [member],
      ),
      isNull,
    );
  });

  test(
    'deduplica avisos y rompe confianza al cambiar identidad local',
    () async {
      final platform = _Platform();
      final mesh = MeshController(platform: platform, repository: _Messages());
      await mesh.initialize();
      final families = _Families([member]);
      final notifications = _Notifications();
      final controller = FamilyController(
        mesh: mesh,
        repository: families,
        notifications: notifications,
      );
      await controller.initialize();
      platform.eventsController.add({
        'type': 'snapshot',
        'status': 'active',
        'peerId': 'fedcba9876543210',
        'nickname': 'Yo',
        'signingPublicKey': Uint8List.fromList(List.filled(32, 7)),
        'peers': [
          {
            'id': member.peerId,
            'nickname': member.nickname,
            'lastSeen': 2000,
            'signingPublicKey': key,
          },
        ],
      });
      await pumpEventQueue();
      platform.eventsController.add({
        'type': 'message',
        'message': {
          'id': 'family-drill-1',
          'sender': member.nickname,
          'content':
              'SIMULACRO - no solicita rescate\n'
              '[HB-DRILL|1|CHECKIN|HELP|3000]',
          'senderPeerId': member.peerId,
          'private': false,
          'mine': false,
          'timestamp': 3000,
          'channel': 'drill',
        },
      });
      await pumpEventQueue();
      expect(notifications.messageIds, isEmpty);

      final messageEvent = {
        'type': 'message',
        'message': {
          'id': 'family-sos-1',
          'sender': member.nickname,
          'content': 'SOS|Ayuda||',
          'senderPeerId': member.peerId,
          'private': false,
          'mine': false,
          'timestamp': 3000,
          'channel': 'sos',
        },
      };
      platform.eventsController.add(messageEvent);
      platform.eventsController.add(messageEvent);
      await pumpEventQueue();

      expect(notifications.messageIds, ['family-sos-1']);

      platform.eventsController.add({
        'type': 'status',
        'status': 'active',
        'peerId': 'fedcba9876543210',
        'nickname': 'Yo',
        'signingPublicKey': Uint8List.fromList(List.filled(32, 8)),
      });
      await pumpEventQueue();

      expect(families.clearTrustCalls, 1);
      expect(controller.members, isEmpty);
      controller.dispose();
      mesh.dispose();
      await platform.eventsController.close();
    },
  );
}
