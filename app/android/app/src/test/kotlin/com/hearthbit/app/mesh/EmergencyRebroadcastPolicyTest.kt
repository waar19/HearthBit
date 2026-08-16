package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EmergencyRebroadcastPolicyTest {
    @Test
    fun `active rescue on a running relay schedules rebroadcast`() {
        assertTrue(
            shouldSchedule(
                running = true,
                rescueActive = true,
                role = MeshNodeRole.PHONE_RELAY,
                profile = PowerProfile.BALANCED,
            ),
        )
    }

    @Test
    fun `inactive or stopped mesh never schedules rebroadcast`() {
        assertFalse(
            shouldSchedule(
                running = false,
                rescueActive = true,
                role = MeshNodeRole.PHONE_RELAY,
                profile = PowerProfile.BALANCED,
            ),
        )
        assertFalse(
            shouldSchedule(
                running = true,
                rescueActive = false,
                role = MeshNodeRole.PHONE_RELAY,
                profile = PowerProfile.BALANCED,
            ),
        )
    }

    @Test
    fun `beacon and survival modes never schedule rebroadcast`() {
        assertFalse(
            shouldSchedule(
                running = true,
                rescueActive = true,
                role = MeshNodeRole.PHONE_BEACON,
                profile = PowerProfile.BALANCED,
            ),
        )
        assertFalse(
            shouldSchedule(
                running = true,
                rescueActive = true,
                role = MeshNodeRole.PHONE_RELAY,
                profile = PowerProfile.SURVIVAL,
            ),
        )
    }

    @Test
    fun `rebroadcast interval stays bounded to one minute`() {
        assertTrue(EmergencyRebroadcastPolicy.INTERVAL_MS in 1L..60_000L)
    }

    @Test
    fun `selecciona como maximo el SOS local mas reciente del rescate actual`() {
        val local = ByteArray(8) { 1 }
        val remote = ByteArray(8) { 2 }
        val selected = EmergencyRebroadcastPolicy.selectLocalSos(
            packets = listOf(
                packet(local, 99, "SOS|antiguo||"),
                packet(remote, 300, "SOS|remoto||"),
                packet(local, 200, "Estoy bien [HB-CHECKIN|OK|1|||1]"),
                packet(local, 150, "SOS|actual||"),
                packet(local, 250, "SOS|mas reciente||"),
            ),
            localSenderId = local,
            startedAt = 100,
        )

        assertEquals(250L, selected?.timestamp)
        assertEquals("SOS|mas reciente||", selected?.payload?.toString(Charsets.UTF_8))
    }

    @Test
    fun `no retransmite si no existe SOS local posterior al inicio`() {
        val local = ByteArray(8) { 1 }

        assertNull(
            EmergencyRebroadcastPolicy.selectLocalSos(
                packets = listOf(packet(local, 99, "SOS|antiguo||")),
                localSenderId = local,
                startedAt = 100,
            ),
        )
    }

    private fun shouldSchedule(
        running: Boolean,
        rescueActive: Boolean,
        role: MeshNodeRole,
        profile: PowerProfile,
    ): Boolean = EmergencyRebroadcastPolicy.shouldSchedule(
        running = running,
        rescueActive = rescueActive,
        role = role,
        powerProfile = profile,
    )

    private fun packet(sender: ByteArray, timestamp: Long, content: String) =
        MeshProtocol.Packet(
            type = MeshProtocol.TYPE_MESSAGE,
            ttl = MeshProtocol.TTL,
            timestamp = timestamp,
            senderId = sender,
            payload = content.toByteArray(),
        )
}
