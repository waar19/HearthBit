package com.hearthbit.app.mesh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MeshtasticDeliveryQueueTest {
    @Test
    fun `full queue rejects standard and critical when no standard can be evicted`() {
        val standardQueue = MeshtasticDeliveryQueue(capacity = 2)
        assertEquals(enqueued, standardQueue.offer(frame(1), LinkPriority.STANDARD))
        assertEquals(enqueued, standardQueue.offer(frame(2), LinkPriority.STANDARD))
        assertEquals(rejected, standardQueue.offer(frame(3), LinkPriority.STANDARD))
        assertEquals(2, standardQueue.size)

        val criticalQueue = MeshtasticDeliveryQueue(capacity = 2)
        assertEquals(enqueued, criticalQueue.offer(frame(10), LinkPriority.CRITICAL))
        assertEquals(enqueued, criticalQueue.offer(frame(11), LinkPriority.CRITICAL))
        assertEquals(rejected, criticalQueue.offer(frame(12), LinkPriority.CRITICAL))
        assertEquals(2, criticalQueue.size)
    }

    @Test
    fun `critical frame evicts oldest standard frame when full`() {
        val queue = MeshtasticDeliveryQueue(capacity = 2)
        queue.offer(frame(1), LinkPriority.STANDARD)
        queue.offer(frame(2), LinkPriority.STANDARD)

        assertEquals(evicted, queue.offer(frame(9), LinkPriority.CRITICAL))
        assertEquals(2, queue.size)
        assertArrayEquals(frame(9), queue.poll())
        assertArrayEquals(frame(2), queue.poll())
    }

    @Test
    fun `frames remain FIFO within each priority`() {
        val queue = MeshtasticDeliveryQueue(capacity = 6)
        queue.offer(frame(1), LinkPriority.STANDARD)
        queue.offer(frame(2), LinkPriority.STANDARD)
        queue.offer(frame(10), LinkPriority.CRITICAL)
        queue.offer(frame(11), LinkPriority.CRITICAL)

        assertArrayEquals(frame(10), queue.poll())
        assertArrayEquals(frame(11), queue.poll())
        assertArrayEquals(frame(1), queue.poll())
        assertArrayEquals(frame(2), queue.poll())
    }

    @Test
    fun `standard frame gets a turn after default burst of eight critical frames`() {
        val queue = MeshtasticDeliveryQueue(capacity = 10)
        queue.offer(frame(1), LinkPriority.STANDARD)
        repeat(9) { index ->
            queue.offer(frame(10 + index), LinkPriority.CRITICAL)
        }

        repeat(8) { index ->
            assertArrayEquals(frame(10 + index), queue.poll())
        }
        assertArrayEquals(frame(1), queue.poll())
        assertArrayEquals(frame(18), queue.poll())
    }

    @Test
    fun `clear removes all frames and resets burst accounting`() {
        val queue = MeshtasticDeliveryQueue(capacity = 3, maxCriticalBurst = 1)
        queue.offer(frame(10), LinkPriority.CRITICAL)
        queue.poll()
        queue.offer(frame(1), LinkPriority.STANDARD)
        queue.offer(frame(11), LinkPriority.CRITICAL)

        queue.clear()

        assertEquals(0, queue.size)
        assertNull(queue.poll())
        queue.offer(frame(2), LinkPriority.STANDARD)
        queue.offer(frame(12), LinkPriority.CRITICAL)
        assertArrayEquals(frame(12), queue.poll())
    }

    private fun frame(value: Int): ByteArray = byteArrayOf(value.toByte())

    private companion object {
        val enqueued = MeshtasticQueueOfferResult.ENQUEUED
        val evicted = MeshtasticQueueOfferResult.EVICTED_STANDARD
        val rejected = MeshtasticQueueOfferResult.REJECTED_FULL
    }
}
