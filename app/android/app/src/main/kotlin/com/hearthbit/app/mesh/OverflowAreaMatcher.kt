package com.hearthbit.app.mesh

internal object OverflowAreaMatcher {
    const val APPLE_MANUFACTURER_ID = 0x004C
    private const val OVERFLOW_TYPE = 0x01
    private const val MASK_SIZE = 16

    fun extractMask(manufacturerData: ByteArray?): ByteArray? {
        if (manufacturerData == null || manufacturerData.size < MASK_SIZE + 1) return null
        if (manufacturerData[0].toInt() and 0xFF != OVERFLOW_TYPE) return null
        return manufacturerData.copyOfRange(1, MASK_SIZE + 1)
    }

    fun hasAnyService(mask: ByteArray): Boolean =
        mask.size == MASK_SIZE && mask.any { it.toInt() and 0xFF != 0 }

    fun matchesBit(mask: ByteArray, bitPosition: Int): Boolean {
        if (mask.size != MASK_SIZE || bitPosition !in 0 until MASK_SIZE * 8) return false
        val byteIndex = bitPosition / 8
        val bitIndex = bitPosition % 8
        return mask[byteIndex].toInt() and (1 shl bitIndex) != 0
    }

    fun singleSetBit(mask: ByteArray): Int? {
        if (mask.size != MASK_SIZE) return null
        var found: Int? = null
        for (bitPosition in 0 until MASK_SIZE * 8) {
            if (!matchesBit(mask, bitPosition)) continue
            if (found != null) return null
            found = bitPosition
        }
        return found
    }

    fun toHex(mask: ByteArray): String =
        mask.joinToString(separator = "") { byte -> "%02x".format(byte.toInt() and 0xFF) }
}
