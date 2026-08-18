package com.hearthbit.app.mesh

internal class MeshSessionPeerHistory(
    private val peersWithSessionHistory: MutableSet<String>,
    private val relationshipSecureStore: KeystoreSecureStore,
) {
    @Synchronized
    fun remember(peerIdHex: String) {
        if (!peersWithSessionHistory.add(peerIdHex)) return
        val overflow = peersWithSessionHistory.size - MeshEngineConstants.MAX_REMEMBERED_SESSION_PEERS
        if (overflow > 0) {
            peersWithSessionHistory.asSequence()
                .filterNot { it == peerIdHex }
                .take(overflow)
                .toList()
                .forEach(peersWithSessionHistory::remove)
        }
        check(
            relationshipSecureStore.putStringSet(
                MeshEngineConstants.KEY_SESSION_PEERS,
                peersWithSessionHistory.toSet(),
            ),
        )
    }
}
