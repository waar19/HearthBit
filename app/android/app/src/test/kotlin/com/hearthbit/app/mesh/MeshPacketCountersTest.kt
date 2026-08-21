package com.hearthbit.app.mesh

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshPacketCountersTest {
    @Test
    fun `snapshot preserves exact aggregate semantics`() {
        val counters = MeshPacketCounters()

        counters.recordReceived()
        counters.recordAccepted()
        counters.recordRejected()
        counters.recordForwarded()
        counters.recordDeduplicated()
        counters.recordDroppedRateLimit()
        counters.recordDroppedTtl()
        counters.recordFailedTransport()

        assertEquals(
            mapOf(
                "packetsReceived" to 1L,
                "packetsAccepted" to 1L,
                "packetsRejected" to 1L,
                "packetsForwarded" to 1L,
                "packetsDeduplicated" to 1L,
                "packetsExpired" to 0L,
                "packetsDroppedRateLimit" to 1L,
                "packetsDroppedTtl" to 1L,
                "packetsFailedTransport" to 1L,
            ),
            counters.snapshot(),
        )
    }

    @Test
    fun `ingress rejection separates rate limits from permanent rejects`() {
        val counters = MeshPacketCounters()

        counters.recordIngressRejection(rateLimited = true)
        counters.recordIngressRejection(rateLimited = false)

        assertEquals(1L, counters.snapshot()["packetsDroppedRateLimit"])
        assertEquals(1L, counters.snapshot()["packetsRejected"])
    }

    @Test
    fun `queue full callback does not double count synchronous rejection`() {
        val counters = MeshPacketCounters()

        counters.recordFailedTransport()
        counters.recordGattDeliveryFailure("queueFull")
        counters.recordGattDeliveryFailure("writeFailed")

        assertEquals(2L, counters.snapshot()["packetsFailedTransport"])
    }

    @Test
    fun `increments are thread safe`() {
        val counters = MeshPacketCounters()
        val workers = 8
        val increments = 1_000
        val done = CountDownLatch(workers)
        val executor = Executors.newFixedThreadPool(workers)

        repeat(workers) {
            executor.execute {
                repeat(increments) { counters.recordReceived() }
                done.countDown()
            }
        }

        check(done.await(5, TimeUnit.SECONDS))
        executor.shutdownNow()
        assertEquals((workers * increments).toLong(), counters.snapshot()["packetsReceived"])
    }

    @Test
    fun `snapshot is coherent while related counters advance`() {
        val counters = MeshPacketCounters()
        val done = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        executor.execute {
            repeat(10_000) {
                counters.recordReceived()
                counters.recordAccepted()
            }
            done.countDown()
        }

        while (!done.await(0, TimeUnit.MILLISECONDS)) {
            val snapshot = counters.snapshot()
            val received = snapshot.getValue("packetsReceived")
            val accepted = snapshot.getValue("packetsAccepted")
            assertTrue(received == accepted || received == accepted + 1L)
        }

        executor.shutdownNow()
        val snapshot = counters.snapshot()
        assertEquals(10_000L, snapshot["packetsReceived"])
        assertEquals(10_000L, snapshot["packetsAccepted"])
    }
}
