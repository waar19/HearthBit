package com.hearthbit.app.mesh

import okio.ByteString.Companion.toByteString
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.meshtastic.proto.Data
import org.meshtastic.proto.FromRadio
import org.meshtastic.proto.MeshPacket
import org.meshtastic.proto.PortNum
import org.meshtastic.proto.ToRadio

class MeshtasticFrameCodecTest {
    @Test
    fun `encapsulates HearthBit frame in private app packet`() {
        val frame = byteArrayOf(1, 2, 3, 4)

        val encoded = MeshtasticFrameCodec.encodeFrame(
            frame = frame,
            packetId = 42,
            requestAck = true,
        )
        val toRadio = ToRadio.ADAPTER.decode(encoded)

        assertTrue(toRadio.packet?.want_ack == true)
        assertTrue(toRadio.packet?.decoded?.portnum == PortNum.PRIVATE_APP)
        assertArrayEquals(frame, toRadio.packet?.decoded?.payload?.toByteArray())
    }

    @Test
    fun `extracts only private app frames`() {
        val frame = byteArrayOf(5, 6, 7)
        val privatePacket = FromRadio(
            packet = MeshPacket(
                decoded = Data(
                    portnum = PortNum.PRIVATE_APP,
                    payload = frame.toByteString(),
                ),
            ),
        ).encode()
        val textPacket = FromRadio(
            packet = MeshPacket(
                decoded = Data(
                    portnum = PortNum.TEXT_MESSAGE_APP,
                    payload = "ignore".encodeToByteArray().toByteString(),
                ),
            ),
        ).encode()

        assertArrayEquals(frame, MeshtasticFrameCodec.decodeFrame(privatePacket))
        assertNull(MeshtasticFrameCodec.decodeFrame(textPacket))
        assertNull(MeshtasticFrameCodec.decodeFrame(byteArrayOf(0x7f)))
    }

    @Test
    fun `rejects frames above LoRa budget`() {
        assertThrows(IllegalArgumentException::class.java) {
            MeshtasticFrameCodec.encodeFrame(
                frame = ByteArray(MeshtasticFrameCodec.MAX_HEARTHBIT_FRAME_BYTES + 1),
                packetId = 1,
                requestAck = false,
            )
        }
    }
}
