package com.hearthbit.app.mesh

internal object NoiseReplayPolicy {
    /**
     * Un paquete Noise anterior al último ANNOUNCE firmado del mismo emisor
     * pertenece a una época de transporte previa y no puede continuar la
     * sesión actual.
     */
    fun isCurrent(packetTimestamp: Long, latestAnnouncementTimestamp: Long?): Boolean =
        latestAnnouncementTimestamp == null || packetTimestamp >= latestAnnouncementTimestamp
}
