package com.hearthbit.app.mesh

/**
 * Contadores agregados, sin PII y con vida igual a la del proceso.
 *
 * received: frame de paquete entregado al ingress, incluso si no decodifica.
 * accepted: paquete decodificado, autenticado/admitido y único.
 * rejected: fallo permanente de decode, autenticación o política; un duplicado
 * no se vuelve a contar como rechazo.
 * deduplicated: fingerprint ya visto o relay aún pendiente.
 * expired: no hay una expiración temporal de paquete observable en este engine;
 * permanece en cero.
 * droppedRateLimit: límites observables de ingress desconocido y emergencia
 * abierta (relaciones known + unknown).
 * droppedTtl: candidato a relay que se procesa localmente pero no se reenvía
 * porque ttl <= 1.
 * forwarded: decisión de relay que alcanza broadcast, una vez por paquete.
 * failedTransport: intento real de enlace rechazado; cuenta intentos de enlace,
 * no paquetes únicos.
 */
internal class MeshPacketCounters {
    private val lock = Any()
    private var packetsReceived = 0L
    private var packetsAccepted = 0L
    private var packetsRejected = 0L
    private var packetsForwarded = 0L
    private var packetsDeduplicated = 0L
    private var packetsDroppedRateLimit = 0L
    private var packetsDroppedTtl = 0L
    private var packetsFailedTransport = 0L

    fun recordReceived(): Long = synchronized(lock) {
        packetsReceived = incrementSaturated(packetsReceived)
        packetsReceived
    }

    fun recordAccepted(): Long = synchronized(lock) {
        packetsAccepted = incrementSaturated(packetsAccepted)
        packetsAccepted
    }

    fun recordRejected(): Long = synchronized(lock) {
        packetsRejected = incrementSaturated(packetsRejected)
        packetsRejected
    }

    fun recordForwarded(): Long = synchronized(lock) {
        packetsForwarded = incrementSaturated(packetsForwarded)
        packetsForwarded
    }

    fun recordDeduplicated(): Long = synchronized(lock) {
        packetsDeduplicated = incrementSaturated(packetsDeduplicated)
        packetsDeduplicated
    }

    fun recordDroppedRateLimit(): Long = synchronized(lock) {
        packetsDroppedRateLimit = incrementSaturated(packetsDroppedRateLimit)
        packetsDroppedRateLimit
    }

    fun recordDroppedTtl(): Long = synchronized(lock) {
        packetsDroppedTtl = incrementSaturated(packetsDroppedTtl)
        packetsDroppedTtl
    }

    fun recordFailedTransport(): Long = synchronized(lock) {
        packetsFailedTransport = incrementSaturated(packetsFailedTransport)
        packetsFailedTransport
    }

    fun recordIngressRejection(rateLimited: Boolean) {
        if (rateLimited) recordDroppedRateLimit() else recordRejected()
    }

    /**
     * queueFull ya fue contado por sendViaLink al recibir false. Los demás
     * callbacks representan fallos asíncronos posteriores.
     */
    fun recordGattDeliveryFailure(reason: String) {
        if (reason != "queueFull") recordFailedTransport()
    }

    fun snapshot(): Map<String, Long> = synchronized(lock) {
        mapOf(
            "packetsReceived" to packetsReceived,
            "packetsAccepted" to packetsAccepted,
            "packetsRejected" to packetsRejected,
            "packetsForwarded" to packetsForwarded,
            "packetsDeduplicated" to packetsDeduplicated,
            "packetsExpired" to 0L,
            "packetsDroppedRateLimit" to packetsDroppedRateLimit,
            "packetsDroppedTtl" to packetsDroppedTtl,
            "packetsFailedTransport" to packetsFailedTransport,
        )
    }

    private fun incrementSaturated(value: Long): Long =
        if (value == Long.MAX_VALUE) Long.MAX_VALUE else value + 1L
}
