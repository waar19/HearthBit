package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BoundedPeerPendingQueueTest {
    @Test
    fun `aplica los limites recomendados por peer y globalmente`() {
        val perPeerQueue = BoundedPeerPendingQueue<Int>()
        repeat(65) { perPeerQueue.offer("peer", it) }

        assertEquals(64, perPeerQueue.size)
        assertEquals((1..64).toList(), perPeerQueue.drain("peer"))

        val peerQueue = BoundedPeerPendingQueue<Int>()
        repeat(257) { peerQueue.offer("peer-$it", it) }

        assertEquals(256, peerQueue.peerCount)
        assertFalse(peerQueue.hasPending("peer-0"))
        assertTrue(peerQueue.hasPending("peer-256"))

        val globalQueue = BoundedPeerPendingQueue<Int>()
        repeat(17) { peer ->
            repeat(64) { item ->
                globalQueue.offer("peer-$peer", item)
            }
        }

        assertEquals(1_024, globalQueue.size)
        assertFalse(globalQueue.hasPending("peer-0"))
        assertEquals(16, globalQueue.peerCount)
    }

    @Test
    fun `expulsa primero el trabajo mas antiguo no protegido`() {
        val queue = BoundedPeerPendingQueue<String>(
            maximumPeers = 3,
            maximumItemsPerPeer = 3,
            maximumItems = 2,
        )
        queue.offer("protected", "protected-old")
        queue.offer("ordinary", "ordinary-new")

        queue.offer(
            "protected",
            "protected-new",
            protectedPeerIds = setOf("protected"),
        )

        assertEquals(emptyList<String>(), queue.drain("ordinary"))
        assertEquals(
            listOf("protected-old", "protected-new"),
            queue.drain("protected"),
        )
    }

    @Test
    fun `expulsa peers de forma determinista al superar el limite`() {
        val queue = BoundedPeerPendingQueue<Int>(
            maximumPeers = 2,
            maximumItemsPerPeer = 2,
            maximumItems = 4,
        )
        queue.offer("first", 1)
        queue.offer("second", 2)
        queue.offer("third", 3)

        assertFalse(queue.hasPending("first"))
        assertEquals(setOf("second", "third"), queue.peerIds())
    }

    @Test
    fun `mantiene la cota cuando todos los peers estan protegidos`() {
        val queue = BoundedPeerPendingQueue<Int>(
            maximumPeers = 2,
            maximumItemsPerPeer = 1,
            maximumItems = 2,
        )
        queue.offer("first", 1)
        queue.offer("second", 2)

        queue.offer(
            "third",
            3,
            protectedPeerIds = setOf("first", "second", "third"),
        )

        assertEquals(2, queue.peerCount)
        assertEquals(2, queue.size)
        assertFalse(queue.hasPending("first"))
        assertEquals(setOf("second", "third"), queue.peerIds())
    }

    @Test
    fun `drenar conserva FIFO y libera el peer`() {
        val queue = BoundedPeerPendingQueue<Int>(
            maximumPeers = 1,
            maximumItemsPerPeer = 3,
            maximumItems = 3,
        )
        queue.offer("old", 1)
        queue.offer("old", 2)

        assertEquals(listOf(1, 2), queue.drain("old"))
        queue.offer("new", 3)

        assertEquals(1, queue.peerCount)
        assertEquals(listOf(3), queue.drain("new"))
    }
}
