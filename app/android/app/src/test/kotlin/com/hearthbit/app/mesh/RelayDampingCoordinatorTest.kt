package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RelayDampingCoordinatorTest {
    @Test
    fun `counts scheduled expired and policy suppressed relays`() {
        val tasks = mutableListOf<() -> Unit>()
        var relayed = false
        val coordinator = RelayDampingCoordinator(
            localSalt = { "local" },
            scheduler = RelayDampingScheduler { _, task ->
                tasks += task
                RelayDampingCancellation {}
            },
        )

        assertTrue(
            coordinator.schedule(
                fingerprint = "fingerprint",
                emergency = false,
                initialSource = "source-a",
            ) {
                relayed = true
            },
        )
        assertTrue(coordinator.observeDuplicate("fingerprint", "source-b"))
        assertTrue(coordinator.observeDuplicate("fingerprint", "source-c"))

        tasks.single().invoke()

        assertFalse(relayed)
        assertEquals(
            mapOf(
                "relayDampingSuppressed" to 1L,
                "relayDampingScheduled" to 1L,
                "relayDampingExpired" to 1L,
            ),
            coordinator.operationalCounters(),
        )
    }
}
