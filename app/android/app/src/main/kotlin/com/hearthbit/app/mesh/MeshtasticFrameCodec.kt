package com.hearthbit.app.mesh

import okio.ByteString.Companion.toByteString
import org.meshtastic.proto.Data
import org.meshtastic.proto.FromRadio
import org.meshtastic.proto.MeshPacket
import org.meshtastic.proto.PortNum
import org.meshtastic.proto.ToRadio

/**
 * Frontera entre frames opacos HearthBit y la Device API de Meshtastic.
 *
 * Meshtastic solo aporta transporte/radio. No interpreta el contenido ni
 * reemplaza firmas, Noise o cifrado de HearthBit.
 */
internal object MeshtasticFrameCodec {
    const val PRIVATE_PORT_NUMBER = 256
    const val MAX_HEARTHBIT_FRAME_BYTES = 180
    private const val BROADCAST_NODE = -1

    fun configRequest(nonce: Int): ByteArray {
        require(nonce != 0)
        return ToRadio(want_config_id = nonce).encode()
    }

    fun encodeFrame(frame: ByteArray, packetId: Int, requestAck: Boolean): ByteArray {
        require(frame.isNotEmpty())
        require(frame.size <= MAX_HEARTHBIT_FRAME_BYTES) {
            "HearthBit frame exceeds Meshtastic payload budget"
        }
        require(packetId != 0)
        val data = Data(
            portnum = PortNum.PRIVATE_APP,
            payload = frame.toByteString(),
        )
        return ToRadio(
            packet = MeshPacket(
                to = BROADCAST_NODE,
                id = packetId,
                want_ack = requestAck,
                decoded = data,
            ),
        ).encode()
    }

    fun decodeFrame(fromRadioBytes: ByteArray): ByteArray? {
        val decoded = runCatching { FromRadio.ADAPTER.decode(fromRadioBytes) }.getOrNull()
            ?: return null
        val data = decoded.packet?.decoded ?: return null
        if (data.portnum != PortNum.PRIVATE_APP) return null
        val frame = data.payload.toByteArray()
        if (frame.isEmpty() || frame.size > MAX_HEARTHBIT_FRAME_BYTES) return null
        return frame
    }
}
