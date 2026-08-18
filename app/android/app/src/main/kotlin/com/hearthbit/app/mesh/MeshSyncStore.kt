package com.hearthbit.app.mesh

import java.util.Collections
import java.util.concurrent.ConcurrentHashMap

internal class MeshSyncStore(
    private val capacity: Int = MeshEngineConstants.SYNC_STORE_CAPACITY,
) {
    private val syncPackets = Collections.synchronizedMap(
        object : LinkedHashMap<String, MeshProtocol.Packet>(capacity, 0.75f, true) {
            override fun removeEldestEntry(
                eldest: MutableMap.MutableEntry<String, MeshProtocol.Packet>?,
            ): Boolean = size > capacity
        },
    )
    private val syncResponseTimes = ConcurrentHashMap<String, ArrayDeque<Long>>()

    fun remember(packet: MeshProtocol.Packet) {
        if (packet.signature == null ||
            packet.type !in setOf(MeshProtocol.TYPE_ANNOUNCE, MeshProtocol.TYPE_MESSAGE) ||
            packet.recipientId?.contentEquals(MeshProtocol.broadcastRecipient) == false
        ) {
            return
        }
        val now = System.currentTimeMillis()
        if (!isFresh(packet, now) || packet.timestamp > now + MeshEngineConstants.SYNC_FUTURE_SKEW_MS) {
            return
        }
        synchronized(syncPackets) {
            if (packet.type == MeshProtocol.TYPE_ANNOUNCE) {
                val sender = MeshProtocol.hex(packet.senderId)
                if (syncPackets.values.any {
                        it.type == MeshProtocol.TYPE_ANNOUNCE &&
                            MeshProtocol.hex(it.senderId) == sender &&
                            it.timestamp >= packet.timestamp
                    }
                ) {
                    return
                }
                val superseded = syncPackets.filterValues {
                    it.type == MeshProtocol.TYPE_ANNOUNCE &&
                        MeshProtocol.hex(it.senderId) == sender &&
                        it.timestamp <= packet.timestamp
                }.keys
                superseded.forEach(syncPackets::remove)
            }
            syncPackets[MeshProtocol.hex(MeshProtocol.packetId(packet))] = packet
        }
    }

    fun snapshot(now: Long = System.currentTimeMillis()): List<MeshProtocol.Packet> =
        synchronized(syncPackets) {
            val expired = syncPackets.filterValues { !isFresh(it, now) }.keys
            expired.forEach(syncPackets::remove)
            syncPackets.values.sortedByDescending { it.timestamp }
        }

    fun allowSyncResponse(sourceAddress: String, now: Long = System.currentTimeMillis()): Boolean {
        val timestamps = syncResponseTimes.computeIfAbsent(sourceAddress) { ArrayDeque() }
        synchronized(timestamps) {
            while (timestamps.isNotEmpty() &&
                now - timestamps.first() > MeshEngineConstants.SYNC_RATE_WINDOW_MS
            ) {
                timestamps.removeFirst()
            }
            if (timestamps.size >= MeshEngineConstants.SYNC_RATE_MAX_RESPONSES) return false
            timestamps.addLast(now)
            return true
        }
    }

    fun removeAnnouncementsForPeer(peerId: String) {
        synchronized(syncPackets) {
            syncPackets.entries.removeIf { (_, packet) ->
                packet.type == MeshProtocol.TYPE_ANNOUNCE &&
                    MeshProtocol.hex(packet.senderId) == peerId
            }
        }
    }

    fun removeRateLimitForAddress(address: String) {
        syncResponseTimes.remove(address)
    }

    fun clear() {
        syncPackets.clear()
        syncResponseTimes.clear()
    }

    private fun isFresh(packet: MeshProtocol.Packet, now: Long): Boolean {
        val window = if (packet.type == MeshProtocol.TYPE_ANNOUNCE) {
            MeshEngineConstants.SYNC_ANNOUNCE_WINDOW_MS
        } else {
            MeshEngineConstants.SYNC_MESSAGE_WINDOW_MS
        }
        return now < window || packet.timestamp >= now - window
    }
}
