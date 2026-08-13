package com.hearthbit.app.mesh

import java.security.SecureRandom

/**
 * Prepara una trama para un enlace GATT usando el formato FragmentPayload de
 * BitChat: [id 8][index u16 BE][total u16 BE][originalType u8][data...].
 */
internal class MeshPacketFragmenter(
    private val fragmentIdGenerator: () -> ByteArray = {
        ByteArray(MeshProtocol.FRAGMENT_ID_SIZE).also(secureRandom::nextBytes)
    },
) {
    fun prepare(encodedPacket: ByteArray, maximumGattValueSize: Int): List<ByteArray>? {
        val linkLimit = maximumGattValueSize.coerceAtMost(MAX_GATT_VALUE_SIZE)
        if (linkLimit <= 0) return null
        if (encodedPacket.size <= linkLimit) return listOf(encodedPacket.copyOf())

        val packet = MeshProtocol.decode(encodedPacket) ?: return null
        if (packet.type == MeshProtocol.TYPE_FRAGMENT) return null

        // El paquete original, incluida su firma, viaja opaco y sin padding de
        // transporte. Cada fragmento se codifica como un paquete independiente.
        val originalData = MeshProtocol.removeBleTransportPadding(packet, encodedPacket)
        if (originalData.size > MAX_REASSEMBLED_BYTES) return null

        val fragmentId = fragmentIdGenerator()
        if (fragmentId.size != MeshProtocol.FRAGMENT_ID_SIZE) return null

        val emptyFragment = fragmentPacket(
            source = packet,
            fragmentId = fragmentId,
            index = 0,
            total = 1,
            data = ByteArray(0),
        )
        val fixedSize = MeshProtocol.encodeForBle(emptyFragment).size
        var chunkSize = minOf(MAX_FRAGMENT_DATA_SIZE, linkLimit - fixedSize)
        if (chunkSize <= 0) return null

        while (chunkSize > 0) {
            val total = divideRoundingUp(originalData.size, chunkSize)
            if (total > MAX_FRAGMENTS) return null
            val frames = ArrayList<ByteArray>(total)
            var offset = 0
            var fits = true
            for (index in 0 until total) {
                val end = minOf(offset + chunkSize, originalData.size)
                val frame = MeshProtocol.encodeForBle(
                    fragmentPacket(
                        source = packet,
                        fragmentId = fragmentId,
                        index = index,
                        total = total,
                        data = originalData.copyOfRange(offset, end),
                    ),
                )
                if (frame.size > linkLimit) {
                    fits = false
                    break
                }
                frames += frame
                offset = end
            }
            if (fits) return frames
            chunkSize--
        }
        return null
    }

    private fun fragmentPacket(
        source: MeshProtocol.Packet,
        fragmentId: ByteArray,
        index: Int,
        total: Int,
        data: ByteArray,
    ): MeshProtocol.Packet = MeshProtocol.Packet(
        version = source.version,
        type = MeshProtocol.TYPE_FRAGMENT,
        ttl = source.ttl,
        timestamp = source.timestamp,
        senderId = source.senderId,
        recipientId = source.recipientId,
        payload = MeshProtocol.encodeFragmentPayload(
            MeshProtocol.FragmentPayload(
                fragmentId = fragmentId,
                index = index,
                total = total,
                originalType = source.type,
                data = data,
            ),
        ),
        signature = null,
        route = source.route,
        isRsr = false,
    )

    private fun divideRoundingUp(value: Int, divisor: Int): Int =
        ((value.toLong() + divisor - 1L) / divisor).toInt()

    companion object {
        private val secureRandom = SecureRandom()

        const val DEFAULT_ATT_MTU = 23
        const val MAX_ATT_MTU = 517
        const val ATT_PROTOCOL_OVERHEAD = 3
        const val MAX_GATT_VALUE_SIZE = 512
        const val MAX_FRAGMENT_DATA_SIZE = 469
        const val MAX_FRAGMENTS = 256
        const val MAX_REASSEMBLED_BYTES = 1_048_576

        fun maximumGattValueSize(mtu: Int): Int =
            (mtu.coerceIn(ATT_PROTOCOL_OVERHEAD, MAX_ATT_MTU) - ATT_PROTOCOL_OVERHEAD)
                .coerceAtMost(MAX_GATT_VALUE_SIZE)
    }
}
