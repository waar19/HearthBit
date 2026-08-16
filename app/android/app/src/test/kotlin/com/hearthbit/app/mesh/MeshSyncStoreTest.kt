package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MeshSyncStoreTest {
    @Test
    fun `remember keeps newest announce per sender`() {
        val store = MeshSyncStore(capacity = 8)
        val sender = ByteArray(8) { 0x11 }
        val base = System.currentTimeMillis()
        val older = signedAnnounce(sender, timestamp = base - 1_000L, nickname = "old")
        val newer = signedAnnounce(sender, timestamp = base, nickname = "new")

        store.remember(older)
        store.remember(newer)

        val snapshot = store.snapshot(now = base + 1_000L)
        assertEquals(1, snapshot.size)
        assertEquals(base, snapshot.single().timestamp)
    }

    @Test
    fun `snapshot drops expired messages`() {
        val store = MeshSyncStore(capacity = 8)
        val sender = ByteArray(8) { 0x22 }
        val storedAt = System.currentTimeMillis()
        store.remember(
            signedMessage(
                sender,
                timestamp = storedAt,
                content = "SOS|help||",
            ),
        )

        assertEquals(1, store.snapshot(now = storedAt + 1_000L).size)

        val expired = store.snapshot(
            now = storedAt + MeshEngineConstants.SYNC_MESSAGE_WINDOW_MS + 1_000L,
        )
        assertTrue(expired.isEmpty())
    }

    @Test
    fun `allowSyncResponse rate limits per address`() {
        val store = MeshSyncStore()
        val address = "aa:bb:cc:dd:ee:ff"
        val now = 1_000L

        repeat(MeshEngineConstants.SYNC_RATE_MAX_RESPONSES) {
            assertTrue(store.allowSyncResponse(address, now))
        }
        assertFalse(store.allowSyncResponse(address, now))
        assertTrue(
            store.allowSyncResponse(
                address,
                now + MeshEngineConstants.SYNC_RATE_WINDOW_MS + 1,
            ),
        )
    }

    @Test
    fun `removeAnnouncementsForPeer clears only matching sender`() {
        val store = MeshSyncStore(capacity = 8)
        val peerA = ByteArray(8) { 0x01 }
        val peerB = ByteArray(8) { 0x02 }
        val now = System.currentTimeMillis()
        store.remember(signedAnnounce(peerA, timestamp = now, nickname = "a"))
        store.remember(signedAnnounce(peerB, timestamp = now, nickname = "b"))

        store.removeAnnouncementsForPeer(MeshProtocol.hex(peerA))

        val remaining = store.snapshot(now = now + 1_000L)
        assertEquals(1, remaining.size)
        assertEquals(MeshProtocol.hex(peerB), MeshProtocol.hex(remaining.single().senderId))
    }

    private fun signedAnnounce(
        sender: ByteArray,
        timestamp: Long,
        nickname: String,
    ): MeshProtocol.Packet {
        val payload = MeshProtocol.encodeAnnouncement(
            nickname = nickname,
            noisePublicKey = ByteArray(32),
            signingPublicKey = ByteArray(32),
            emergencyPreannounce = false,
        )
        return MeshProtocol.Packet(
            type = MeshProtocol.TYPE_ANNOUNCE,
            ttl = 7,
            timestamp = timestamp,
            senderId = sender,
            payload = payload,
            signature = ByteArray(64),
        )
    }

    private fun signedMessage(
        sender: ByteArray,
        timestamp: Long,
        content: String,
    ): MeshProtocol.Packet = MeshProtocol.Packet(
        type = MeshProtocol.TYPE_MESSAGE,
        ttl = 7,
        timestamp = timestamp,
        senderId = sender,
        payload = MeshProtocol.encodeInteropPublicMessage(content),
        signature = ByteArray(64),
    )
}
