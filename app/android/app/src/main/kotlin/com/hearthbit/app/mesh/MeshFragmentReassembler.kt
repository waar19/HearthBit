package com.hearthbit.app.mesh

import java.io.ByteArrayOutputStream

/**
 * Reensambla TYPE_FRAGMENT (0x20) con el formato actual de BitChat:
 * [id 8][index u16 BE][total u16 BE][originalType u8][data...].
 */
internal class MeshFragmentReassembler {
    private data class FragmentSet(
        val originalType: Byte,
        val total: Int,
        val senderId: ByteArray,
        val recipientId: ByteArray?,
        var updatedAt: Long,
        val parts: MutableMap<Int, ByteArray> = mutableMapOf(),
        var bytes: Int = 0,
    )

    private data class Fragment(
        val id: ByteArray,
        val index: Int,
        val total: Int,
        val originalType: Byte,
        val data: ByteArray,
    )

    private val lock = Any()
    private val sets = mutableMapOf<String, FragmentSet>()
    private var bufferedBytes = 0L

    fun accept(
        packet: MeshProtocol.Packet,
        now: Long = System.currentTimeMillis(),
    ): MeshProtocol.Packet? {
        if (packet.type != MeshProtocol.TYPE_FRAGMENT) return null
        val fragment = decode(packet.payload) ?: return null
        synchronized(lock) {
            pruneExpired(now)
            val key = "${MeshProtocol.hex(packet.senderId)}:${MeshProtocol.hex(fragment.id)}"
            val set = sets[key] ?: run {
                if (sets.size >= MAX_ACTIVE_SETS) return null
                FragmentSet(
                    originalType = fragment.originalType,
                    total = fragment.total,
                    senderId = packet.senderId.copyOf(),
                    recipientId = packet.recipientId?.copyOf(),
                    updatedAt = now,
                ).also { sets[key] = it }
            }
            if (
                set.originalType != fragment.originalType ||
                set.total != fragment.total ||
                !set.senderId.contentEquals(packet.senderId) ||
                !sameRecipient(set.recipientId, packet.recipientId)
            ) {
                remove(key)
                return null
            }

            val existing = set.parts[fragment.index]
            if (existing != null) {
                if (!existing.contentEquals(fragment.data)) remove(key)
                return null
            }
            if (set.bytes + fragment.data.size > MAX_SET_BYTES ||
                bufferedBytes + fragment.data.size > MAX_GLOBAL_BYTES
            ) {
                remove(key)
                return null
            }

            set.parts[fragment.index] = fragment.data
            set.bytes += fragment.data.size
            set.updatedAt = now
            bufferedBytes += fragment.data.size
            if (set.parts.size != set.total) return null

            val output = ByteArrayOutputStream(set.bytes)
            for (index in 0 until set.total) {
                val part = set.parts[index] ?: return null
                output.write(part)
            }
            val decoded = MeshProtocol.decode(output.toByteArray())
            remove(key)
            if (decoded == null ||
                decoded.type != set.originalType ||
                !decoded.senderId.contentEquals(packet.senderId) ||
                !sameRecipient(decoded.recipientId, packet.recipientId)
            ) {
                return null
            }
            // El paquete original ya viajó dentro de fragments que fueron
            // retransmitidos individualmente; no volver a retransmitirlo.
            return decoded.copy(ttl = 0)
        }
    }

    fun clear() {
        synchronized(lock) {
            sets.clear()
            bufferedBytes = 0
        }
    }

    private fun decode(payload: ByteArray): Fragment? {
        if (payload.size <= HEADER_SIZE) return null
        val index = ((payload[8].toInt() and 0xFF) shl 8) or
            (payload[9].toInt() and 0xFF)
        val total = ((payload[10].toInt() and 0xFF) shl 8) or
            (payload[11].toInt() and 0xFF)
        if (total !in 1..MAX_FRAGMENTS || index !in 0 until total) return null
        return Fragment(
            id = payload.copyOfRange(0, 8),
            index = index,
            total = total,
            originalType = payload[12],
            data = payload.copyOfRange(HEADER_SIZE, payload.size),
        )
    }

    private fun pruneExpired(now: Long) {
        sets.filterValues { now - it.updatedAt > TIMEOUT_MS }
            .keys
            .toList()
            .forEach(::remove)
    }

    private fun remove(key: String) {
        val removed = sets.remove(key) ?: return
        bufferedBytes = (bufferedBytes - removed.bytes).coerceAtLeast(0)
    }

    private fun sameRecipient(first: ByteArray?, second: ByteArray?): Boolean =
        first == null && second == null ||
            first != null && second != null && first.contentEquals(second)

    private companion object {
        const val HEADER_SIZE = 13
        const val MAX_FRAGMENTS = 256
        const val MAX_SET_BYTES = 1_048_576
        const val MAX_ACTIVE_SETS = 64
        const val MAX_GLOBAL_BYTES = 4L * 1_048_576L
        const val TIMEOUT_MS = 30_000L
    }
}
