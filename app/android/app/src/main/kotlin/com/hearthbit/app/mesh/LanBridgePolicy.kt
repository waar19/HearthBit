package com.hearthbit.app.mesh

internal object LanBridgePolicy {
    const val MAX_FRAME_SIZE = 65_535

    fun validateGatewayId(value: String?): String {
        val normalized = requireNotNull(value).lowercase()
        require(normalized.matches(Regex("[0-9a-f]{32}"))) {
            "Identificador de gateway LAN no válido"
        }
        return normalized
    }

    fun validateMaximumFrameSize(value: Int): Int {
        require(value in 1..MAX_FRAME_SIZE) {
            "Límite de frame LAN no válido"
        }
        return value
    }

    fun validateFrame(frame: ByteArray, maximumFrameSize: Int): ByteArray {
        require(frame.isNotEmpty() && frame.size <= maximumFrameSize) {
            "Frame LAN fuera de límites"
        }
        return frame.copyOf()
    }

    fun shouldClearOnStop(notify: Boolean): Boolean = notify
}
