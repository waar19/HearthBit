package com.hearthbit.app.mesh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LinkAdapterTest {
    @Test
    fun `expone capacidades estructuradas y conserva el frame opaco`() {
        val capabilities = LinkCapabilities(
            id = "memory:test",
            kind = LinkKind.IN_MEMORY,
            mtu = 4,
            broadcast = true,
            unicast = true,
            reliability = LinkReliability.ACKNOWLEDGED,
            background = true,
            maxConnections = 3,
            cost = 0,
        )
        val link = InMemoryLinkAdapter(capabilities)
        val frame = byteArrayOf(1, 2, 3, 4)

        assertTrue(link.send(frame))
        frame[0] = 9

        assertEquals(capabilities, link.capabilities)
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), link.sentFrames().single())
    }

    @Test
    fun `rechaza frames mayores al MTU`() {
        val link = InMemoryLinkAdapter(
            LinkCapabilities(
                id = "memory:small",
                kind = LinkKind.IN_MEMORY,
                mtu = 2,
                broadcast = false,
                unicast = true,
                reliability = LinkReliability.BEST_EFFORT,
                background = false,
                maxConnections = 1,
                cost = 1,
            ),
        )

        assertFalse(link.send(byteArrayOf(1, 2, 3)))
        assertTrue(link.sentFrames().isEmpty())
    }
}
