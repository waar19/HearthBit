package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test

class RelayDampingPolicyTest {
    @Test
    fun `normal and emergency parameters match the shared protocol`() {
        assertEquals(
            RelayDampingParameters(180L, 420L, 2),
            RelayDampingPolicy.parameters(emergency = false),
        )
        assertEquals(
            RelayDampingParameters(80L, 160L, 3),
            RelayDampingPolicy.parameters(emergency = true),
        )
    }

    @Test
    fun `jitter is deterministic and depends on local identity`() {
        val first = RelayDampingPolicy.jitterMs(
            fingerprint = "relay-fingerprint",
            localSalt = "node-a",
            emergency = false,
        )

        assertEquals(
            first,
            RelayDampingPolicy.jitterMs(
                fingerprint = "relay-fingerprint",
                localSalt = "node-a",
                emergency = false,
            ),
        )
        assertNotEquals(
            first,
            RelayDampingPolicy.jitterMs(
                fingerprint = "relay-fingerprint",
                localSalt = "node-b",
                emergency = false,
            ),
        )
    }

    @Test
    fun `jitter includes both normal and emergency limits`() {
        assertEquals(180L, jitter("fingerprint-59", emergency = false))
        assertEquals(420L, jitter("fingerprint-301", emergency = false))
        assertEquals(80L, jitter("fingerprint-236", emergency = true))
        assertEquals(160L, jitter("fingerprint-102", emergency = true))

        repeat(2_000) { index ->
            assertTrue(jitter("normal-$index", emergency = false) in 180L..420L)
            assertTrue(jitter("emergency-$index", emergency = true) in 80L..160L)
        }
    }

    @Test
    fun `normal relay is suppressed after two additional copies`() {
        assertTrue(RelayDampingPolicy.shouldRelay(0, emergency = false))
        assertTrue(RelayDampingPolicy.shouldRelay(1, emergency = false))
        assertFalse(RelayDampingPolicy.shouldRelay(2, emergency = false))
        assertFalse(RelayDampingPolicy.shouldRelay(Int.MAX_VALUE, emergency = false))
    }

    @Test
    fun `emergency relay tolerates two copies and suppresses at three`() {
        assertTrue(RelayDampingPolicy.shouldRelay(0, emergency = true))
        assertTrue(RelayDampingPolicy.shouldRelay(1, emergency = true))
        assertTrue(RelayDampingPolicy.shouldRelay(2, emergency = true))
        assertFalse(RelayDampingPolicy.shouldRelay(3, emergency = true))
        assertFalse(RelayDampingPolicy.shouldRelay(Int.MAX_VALUE, emergency = true))
    }

    @Test
    fun `negative copy count is rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            RelayDampingPolicy.shouldRelay(-1, emergency = false)
        }
    }

    @Test
    fun `repeated duplicates from one source do not suppress relay`() {
        val scheduler = FakeRelayScheduler()
        var relays = 0
        val coordinator = coordinator(scheduler)

        coordinator.schedule(
            fingerprint = "normal",
            emergency = false,
            initialSource = "neighbor-a",
        ) {
            relays += 1
        }
        assertFalse(coordinator.observeDuplicate("normal", "neighbor-a"))
        assertFalse(coordinator.observeDuplicate("normal", "neighbor-a"))
        scheduler.run(0)

        assertEquals(1, relays)
        assertEquals(0, coordinator.pendingCount())
    }

    @Test
    fun `distinct duplicate sources suppress normal relay`() {
        val scheduler = FakeRelayScheduler()
        var relays = 0
        val coordinator = coordinator(scheduler)

        coordinator.schedule(
            fingerprint = "normal",
            emergency = false,
            initialSource = "neighbor-a",
        ) {
            relays += 1
        }
        assertTrue(coordinator.observeDuplicate("normal", "neighbor-b"))
        assertTrue(coordinator.observeDuplicate("normal", "neighbor-c"))
        assertFalse(coordinator.observeDuplicate("normal", "neighbor-c"))
        scheduler.run(0)

        assertEquals(0, relays)
    }

    @Test
    fun `emergency relay tolerates two distinct duplicate sources`() {
        val scheduler = FakeRelayScheduler()
        var relays = 0
        val coordinator = coordinator(scheduler)

        coordinator.schedule(
            fingerprint = "emergency",
            emergency = true,
            initialSource = "neighbor-a",
        ) {
            relays += 1
        }
        assertTrue(coordinator.observeDuplicate("emergency", "neighbor-b"))
        assertTrue(coordinator.observeDuplicate("emergency", "neighbor-c"))
        scheduler.run(0)

        assertEquals(1, relays)
        assertEquals(0, coordinator.pendingCount())
    }

    @Test
    fun `null source uses one stable source key`() {
        val scheduler = FakeRelayScheduler()
        var relays = 0
        val coordinator = coordinator(scheduler)

        coordinator.schedule("null-source", emergency = false, initialSource = null) {
            relays += 1
        }
        assertFalse(coordinator.observeDuplicate("null-source", null))
        assertFalse(coordinator.observeDuplicate("null-source", null))
        assertTrue(coordinator.observeDuplicate("null-source", "neighbor-b"))
        scheduler.run(0)

        assertEquals(1, relays)
    }

    @Test
    fun `coordinator bounds pending relays and safely cancels eviction`() {
        val scheduler = FakeRelayScheduler()
        val relayed = mutableListOf<String>()
        val coordinator = coordinator(scheduler, maximumPendingRelays = 2)

        coordinator.schedule("first", emergency = false, initialSource = "a") {
            relayed += "first"
        }
        coordinator.schedule("second", emergency = false, initialSource = "a") {
            relayed += "second"
        }
        coordinator.schedule("third", emergency = false, initialSource = "a") {
            relayed += "third"
        }

        assertEquals(2, coordinator.pendingCount())
        assertTrue(scheduler.task(0).cancelled)
        scheduler.run(0)
        scheduler.run(1)
        scheduler.run(2)
        assertEquals(listOf("second", "third"), relayed)
    }

    @Test
    fun `clear cancels every callback and duplicate schedules are ignored`() {
        val scheduler = FakeRelayScheduler()
        var relays = 0
        val coordinator = coordinator(scheduler)

        assertTrue(
            coordinator.schedule("same", emergency = false, initialSource = "a") {
                relays += 1
            },
        )
        assertFalse(
            coordinator.schedule("same", emergency = false, initialSource = "b") {
                relays += 1
            },
        )
        assertFalse(coordinator.observeDuplicate("missing", "a"))
        coordinator.clear()

        assertEquals(0, coordinator.pendingCount())
        assertTrue(scheduler.task(0).cancelled)
        scheduler.run(0)
        assertEquals(0, relays)
    }

    @Test
    fun `coordinator schedules emergency before normal traffic`() {
        val scheduler = FakeRelayScheduler()
        val coordinator = coordinator(scheduler)

        coordinator.schedule("normal-delay", emergency = false, initialSource = "a") {}
        coordinator.schedule("emergency-delay", emergency = true, initialSource = "a") {}

        assertTrue(scheduler.task(0).delayMs in 180L..420L)
        assertTrue(scheduler.task(1).delayMs in 80L..160L)
        assertTrue(
            scheduler.task(1).delayMs <
                scheduler.task(0).delayMs,
        )
    }

    private fun jitter(fingerprint: String, emergency: Boolean): Long =
        RelayDampingPolicy.jitterMs(
            fingerprint = fingerprint,
            localSalt = "node-a",
            emergency = emergency,
        )

    private fun coordinator(
        scheduler: FakeRelayScheduler,
        maximumPendingRelays: Int = RelayDampingCoordinator.MAXIMUM_PENDING_RELAYS,
    ): RelayDampingCoordinator = RelayDampingCoordinator(
        localSalt = { "node-a" },
        scheduler = scheduler,
        maximumPendingRelays = maximumPendingRelays,
    )

    private class FakeRelayScheduler : RelayDampingScheduler {
        data class ScheduledTask(
            val delayMs: Long,
            val action: () -> Unit,
            var cancelled: Boolean = false,
        )

        private val tasks = mutableListOf<ScheduledTask>()

        override fun schedule(
            delayMs: Long,
            task: () -> Unit,
        ): RelayDampingCancellation {
            val scheduled = ScheduledTask(
                delayMs = delayMs,
                action = task,
            )
            tasks += scheduled
            return RelayDampingCancellation { scheduled.cancelled = true }
        }

        fun task(index: Int): ScheduledTask = tasks[index]

        fun run(index: Int) {
            task(index).action()
        }
    }
}
