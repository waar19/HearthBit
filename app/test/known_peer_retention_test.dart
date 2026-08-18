import 'package:flutter_test/flutter_test.dart';
import 'package:hearth_bit/models/mesh_models.dart';
import 'package:hearth_bit/utils/known_peer_retention.dart';

MeshPeer _peer(String id, int lastSeen) => MeshPeer(
  id: id,
  nickname: id,
  lastSeen: DateTime.fromMillisecondsSinceEpoch(lastSeen),
  secure: false,
);

void main() {
  test('limita peers conocidos y prioriza activos, mensajes y pendientes', () {
    final retained = retainKnownPeers(
      peers: [
        for (var index = 0; index < 12; index++) _peer('peer-$index', index),
      ],
      activePeerIds: const {'peer-0'},
      messagePeerIds: const {'peer-1'},
      pendingPeerIds: const {'peer-2'},
      maximumPeers: 5,
    );

    expect(retained, hasLength(5));
    expect(retained.map((peer) => peer.id), [
      'peer-0',
      'peer-2',
      'peer-1',
      'peer-11',
      'peer-10',
    ]);
  });

  test('mantiene el máximo estricto si hay más protegidos que capacidad', () {
    final retained = retainKnownPeers(
      peers: [
        for (var index = 0; index < 6; index++) _peer('peer-$index', index),
      ],
      activePeerIds: const {'peer-0', 'peer-1', 'peer-2', 'peer-3'},
      messagePeerIds: const {},
      pendingPeerIds: const {},
      maximumPeers: 3,
    );

    expect(retained.map((peer) => peer.id), ['peer-3', 'peer-2', 'peer-1']);
  });
}
