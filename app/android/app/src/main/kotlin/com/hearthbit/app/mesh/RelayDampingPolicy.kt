package com.hearthbit.app.mesh

import java.security.MessageDigest

internal data class RelayDampingParameters(
    val minimumJitterMs: Long,
    val maximumJitterMs: Long,
    val suppressionThreshold: Int,
)

internal object RelayDampingPolicy {
    val NORMAL = RelayDampingParameters(
        minimumJitterMs = 180L,
        maximumJitterMs = 420L,
        suppressionThreshold = 2,
    )
    val EMERGENCY = RelayDampingParameters(
        minimumJitterMs = 80L,
        maximumJitterMs = 160L,
        suppressionThreshold = 3,
    )

    fun parameters(emergency: Boolean): RelayDampingParameters =
        if (emergency) EMERGENCY else NORMAL

    fun jitterMs(
        fingerprint: String,
        localSalt: String,
        emergency: Boolean,
    ): Long {
        val parameters = parameters(emergency)
        val digest = MessageDigest.getInstance("SHA-256").apply {
            update(fingerprint.toByteArray(Charsets.UTF_8))
            update(byteArrayOf(0))
            update(localSalt.toByteArray(Charsets.UTF_8))
        }.digest()
        var sample = 0L
        repeat(Long.SIZE_BYTES) { index ->
            sample = (sample shl Byte.SIZE_BITS) or (digest[index].toLong() and 0xFFL)
        }
        val possibilities = parameters.maximumJitterMs - parameters.minimumJitterMs + 1L
        return parameters.minimumJitterMs +
            java.lang.Long.remainderUnsigned(sample, possibilities)
    }

    fun shouldRelay(additionalCopies: Int, emergency: Boolean): Boolean {
        require(additionalCopies >= 0)
        return additionalCopies < parameters(emergency).suppressionThreshold
    }
}
