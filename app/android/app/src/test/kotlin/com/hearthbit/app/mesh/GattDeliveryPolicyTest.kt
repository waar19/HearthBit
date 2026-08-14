package com.hearthbit.app.mesh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GattDeliveryPolicyTest {
    @Test
    fun `critical frames evict normal frames when nominal queue is full`() {
        val queue = GattDeliveryQueue(capacity = 3, criticalOverflow = 1)
        assertTrue(queue.enqueue(listOf(frame(1), frame(2), frame(3)), isCritical = false))

        assertTrue(queue.enqueue(listOf(frame(9)), isCritical = true))
        assertArrayEquals(frame(9), queue.next()!!.bytes)
        assertEquals(3, queue.size)
    }

    @Test
    fun `critical queue has bounded emergency overflow`() {
        val queue = GattDeliveryQueue(capacity = 2, criticalOverflow = 2)

        assertTrue(queue.enqueue(List(4) { frame(it) }, isCritical = true))
        assertFalse(queue.enqueue(listOf(frame(5)), isCritical = true))
    }

    @Test
    fun `failed write remains queued until retry budget is exhausted`() {
        val queue = GattDeliveryQueue(capacity = 2, maxRetries = 2)
        queue.enqueue(listOf(frame(7)), isCritical = true)
        val original = queue.next()

        assertTrue(queue.complete(success = false) is GattDeliveryOutcome.Retry)
        assertTrue(original === queue.next())
        assertTrue(queue.complete(success = false) is GattDeliveryOutcome.Retry)
        val failed = queue.complete(success = false) as GattDeliveryOutcome.Failed

        assertTrue(failed.frame.critical)
        assertEquals(3, failed.frame.failedAttempts)
        assertEquals(0, queue.size)
    }

    @Test
    fun `normal traffic gets a turn during sustained critical traffic`() {
        val queue = GattDeliveryQueue(
            capacity = 20,
            criticalOverflow = 0,
            maxCriticalBurst = 2,
        )
        queue.enqueue(listOf(frame(1)), isCritical = false)
        queue.enqueue(List(4) { frame(10 + it) }, isCritical = true)

        assertArrayEquals(frame(10), queue.next()!!.bytes)
        queue.complete(success = true)
        assertArrayEquals(frame(11), queue.next()!!.bytes)
        queue.complete(success = true)
        assertArrayEquals(frame(1), queue.next()!!.bytes)
    }

    @Test
    fun `SOS packet is classified as critical`() {
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_MESSAGE,
            ttl = MeshProtocol.TTL,
            timestamp = 1,
            senderId = ByteArray(8),
            payload = "SOS|help".toByteArray(),
        )

        assertTrue(GattFramePriority.isCritical(MeshProtocol.encode(packet, padded = false)))
    }

    @Test
    fun `regular message keeps standard priority across local fragmentation`() {
        val packet = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_MESSAGE,
            ttl = MeshProtocol.TTL,
            timestamp = 1,
            senderId = ByteArray(8),
            payload = ByteArray(1_000) { index ->
                (index xor (index shr 3) xor (index * 31)).toByte()
            },
        )
        val encoded = MeshProtocol.encode(packet, padded = false)
        val frames = MeshPacketFragmenter { ByteArray(8) { 1 } }.prepare(encoded, 100)!!
        val propagated = GattFramePriority.forOriginalPacket(encoded)

        assertTrue(frames.size > 1)
        assertEquals(LinkPriority.STANDARD, propagated)
        assertTrue(frames.all { propagated == LinkPriority.STANDARD })
    }

    private fun frame(value: Int): ByteArray = byteArrayOf(value.toByte())
}
