package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class GenericBlePresenceTrackerTest {
    private val secret = ByteArray(32) { it.toByte() }

    @Test
    fun `crea un id local estable dentro de la ventana y no revela datos`() {
        val tracker = GenericBlePresenceTracker(
            sessionSecret = secret,
            rotationMs = 1_000,
            staleAfterMs = 10_000,
            emitIntervalMs = 0,
        )
        val material = "fabricante-estable".toByteArray()

        val first = tracker.observe(material, rssi = -70, now = 100)!!.single()
        val second = tracker.observe(material, rssi = -65, now = 900)!!.single()

        assertEquals(first.localId, second.localId)
        assertEquals(-65, second.rssi)
        assertFalse(second.localId.contains("fabricante"))
        assertEquals(24, second.localId.length)
        assertFalse(second.toEventMap().containsKey("name"))
        assertFalse(second.toEventMap().containsKey("mac"))
        assertEquals(false, second.toEventMap()["chatAvailable"])
    }

    @Test
    fun `rota el id y otra sesion no permite correlacionarlo`() {
        val firstSession = GenericBlePresenceTracker(
            sessionSecret = secret,
            rotationMs = 1_000,
            staleAfterMs = 10_000,
            emitIntervalMs = 0,
        )
        val secondSession = GenericBlePresenceTracker(
            sessionSecret = ByteArray(32) { (it + 1).toByte() },
            rotationMs = 1_000,
            staleAfterMs = 10_000,
            emitIntervalMs = 0,
        )
        val material = byteArrayOf(1, 2, 3)

        val beforeRotation = firstSession.observe(material, -80, 999)!!.single()
        val afterRotation = firstSession.observe(material, -80, 1_000)!!.single()
        val otherSession = secondSession.observe(material, -80, 999)!!.single()

        assertNotEquals(beforeRotation.localId, afterRotation.localId)
        assertNotEquals(beforeRotation.localId, otherSession.localId)
    }

    @Test
    fun `ignora anuncios sin material y elimina presencias vencidas`() {
        val tracker = GenericBlePresenceTracker(
            sessionSecret = secret,
            rotationMs = 1_000,
            staleAfterMs = 100,
            emitIntervalMs = 0,
        )

        assertNull(tracker.observe(byteArrayOf(), -80, 0))
        assertTrue(tracker.observe(byteArrayOf(1), -80, 0)!!.isNotEmpty())
        assertTrue(tracker.snapshot(101).isEmpty())
    }

    @Test
    fun `limita la lista y aplica throttle global en zonas densas`() {
        val tracker = GenericBlePresenceTracker(
            sessionSecret = secret,
            rotationMs = 10_000,
            staleAfterMs = 10_000,
            emitIntervalMs = 1_000,
            maxObservations = 2,
        )

        assertTrue(tracker.observe(byteArrayOf(1), -51, 0)!!.isNotEmpty())
        assertNull(tracker.observe(byteArrayOf(2), -52, 100))
        assertNull(tracker.observe(byteArrayOf(3), -53, 200))

        val bounded = tracker.snapshot(200)
        assertEquals(2, bounded.size)
        assertEquals(setOf(-52, -53), bounded.map { it.rssi }.toSet())
        assertTrue(tracker.observe(byteArrayOf(3), -54, 1_000)!!.isNotEmpty())
    }
}
