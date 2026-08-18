import '../models/mesh_models.dart';

/// Conserva como máximo [maximumPeers], priorizando peers activos, peers con
/// entregas pendientes y peers vinculados a mensajes antes que el resto.
List<MeshPeer> retainKnownPeers({
  required Iterable<MeshPeer> peers,
  required Set<String> activePeerIds,
  required Set<String> messagePeerIds,
  required Set<String> pendingPeerIds,
  int maximumPeers = 1000,
}) {
  if (maximumPeers <= 0) return const [];

  final latestById = <String, MeshPeer>{};
  for (final peer in peers) {
    final existing = latestById[peer.id];
    if (existing == null || peer.lastSeen.isAfter(existing.lastSeen)) {
      latestById[peer.id] = peer;
    }
  }

  int priority(String id) {
    if (activePeerIds.contains(id)) return 0;
    if (pendingPeerIds.contains(id)) return 1;
    if (messagePeerIds.contains(id)) return 2;
    return 3;
  }

  final retained = latestById.values.toList()
    ..sort((first, second) {
      final priorityOrder = priority(first.id).compareTo(priority(second.id));
      if (priorityOrder != 0) return priorityOrder;
      final recencyOrder = second.lastSeen.compareTo(first.lastSeen);
      if (recencyOrder != 0) return recencyOrder;
      return first.id.compareTo(second.id);
    });
  return List.unmodifiable(retained.take(maximumPeers));
}
