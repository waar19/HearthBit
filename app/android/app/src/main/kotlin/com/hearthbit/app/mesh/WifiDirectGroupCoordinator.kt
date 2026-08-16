package com.hearthbit.app.mesh

/**
 * Evita que los dos usuarios de Wi-Fi Direct (SOS y archivos) desmonten el
 * único grupo P2P del sistema mientras el otro todavía lo necesita.
 */
internal object WifiDirectGroupCoordinator {
    @Volatile
    var meshActive: Boolean = false
        private set

    @Volatile
    var transferActive: Boolean = false
        private set

    fun setMeshActive(active: Boolean) {
        meshActive = active
    }

    fun setTransferActive(active: Boolean) {
        transferActive = active
    }

    fun preserveWhenMeshStops(): Boolean = transferActive

    fun preserveWhenTransferStops(): Boolean = meshActive
}
