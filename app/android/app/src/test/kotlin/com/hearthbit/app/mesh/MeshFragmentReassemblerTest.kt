package com.hearthbit.app.mesh

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MeshFragmentReassemblerTest {
    @Test
    fun `reensambla fragments BitChat fuera de orden`() {
        val sender = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8)
        val original = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_MESSAGE,
            ttl = 7,
            timestamp = 1234,
            senderId = sender,
            recipientId = MeshProtocol.broadcastRecipient,
            payload = "Mensaje desde BitChat".toByteArray(),
            signature = ByteArray(64) { 9 },
        )
        val encoded = MeshProtocol.encode(original, padded = false)
        val chunks = encoded.asList().chunked(37).map { it.toByteArray() }
        val fragmentId = byteArrayOf(9, 8, 7, 6, 5, 4, 3, 2)
        val packets = chunks.mapIndexed { index, chunk ->
            MeshProtocol.Packet(
                type = MeshProtocol.TYPE_FRAGMENT,
                ttl = 7,
                timestamp = 1234,
                senderId = sender,
                recipientId = MeshProtocol.broadcastRecipient,
                payload = fragmentPayload(
                    id = fragmentId,
                    index = index,
                    total = chunks.size,
                    originalType = MeshProtocol.TYPE_MESSAGE,
                    data = chunk,
                ),
            )
        }
        val reassembler = MeshFragmentReassembler()

        assertNull(reassembler.accept(packets[1]))
        assertNull(reassembler.accept(packets[1]))
        assertNull(reassembler.accept(packets[0]))
        var result: MeshProtocol.Packet? = null
        for (index in 2 until packets.size) {
            result = reassembler.accept(packets[index]) ?: result
        }

        requireNotNull(result)
        assertEquals(MeshProtocol.TYPE_MESSAGE, result.type)
        assertEquals(0, result.ttl.toInt())
        assertArrayEquals(original.payload, result.payload)
        assertArrayEquals(original.signature, result.signature)
    }

    @Test
    fun `rechaza metadata inconsistente sin mezclar fragmentos`() {
        val sender = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8)
        val id = ByteArray(8) { 1 }
        val reassembler = MeshFragmentReassembler()
        val first = MeshProtocol.Packet(
            type = MeshProtocol.TYPE_FRAGMENT,
            ttl = 7,
            timestamp = 1,
            senderId = sender,
            payload = fragmentPayload(id, 0, 2, MeshProtocol.TYPE_MESSAGE, byteArrayOf(1)),
        )
        val inconsistent = first.copy(
            payload = fragmentPayload(id, 1, 3, MeshProtocol.TYPE_MESSAGE, byteArrayOf(2)),
        )

        assertNull(reassembler.accept(first))
        assertNull(reassembler.accept(inconsistent))
    }

    private fun fragmentPayload(
        id: ByteArray,
        index: Int,
        total: Int,
        originalType: Byte,
        data: ByteArray,
    ): ByteArray = ByteArray(13 + data.size).also { output ->
        id.copyInto(output)
        output[8] = (index shr 8).toByte()
        output[9] = index.toByte()
        output[10] = (total shr 8).toByte()
        output[11] = total.toByte()
        output[12] = originalType
        data.copyInto(output, destinationOffset = 13)
    }
}
