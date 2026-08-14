package com.hearthbit.app.mesh

/**
 * Sliding 1024-nonce replay window. Bit zero represents the watermark and bit
 * N represents watermark-N. State advances only after authenticated decrypt.
 */
internal class NoiseReplayWindow(
    private val windowSize: Int = DEFAULT_WINDOW_SIZE,
) {
    private val bitmap = LongArray((windowSize + Long.SIZE_BITS - 1) / Long.SIZE_BITS)
    private var watermark = -1L

    init {
        require(windowSize > 0 && windowSize % Long.SIZE_BITS == 0)
    }

    fun canAccept(nonce: Long): Boolean {
        if (nonce !in 0..UInt.MAX_VALUE.toLong()) return false
        if (watermark < 0L || nonce > watermark) return true
        val distance = watermark - nonce
        if (distance >= windowSize) return false
        return !isSet(distance.toInt())
    }

    fun recordAuthenticated(nonce: Long) {
        require(canAccept(nonce)) { "Repeated or stale Noise nonce" }
        if (watermark < 0L) {
            watermark = nonce
            set(0)
            return
        }
        if (nonce > watermark) {
            shiftLeft((nonce - watermark).coerceAtMost(windowSize.toLong()).toInt())
            watermark = nonce
            set(0)
            return
        }
        set((watermark - nonce).toInt())
    }

    fun clear() {
        bitmap.fill(0L)
        watermark = -1L
    }

    private fun isSet(bit: Int): Boolean =
        bitmap[bit / Long.SIZE_BITS] and (1L shl (bit % Long.SIZE_BITS)) != 0L

    private fun set(bit: Int) {
        bitmap[bit / Long.SIZE_BITS] =
            bitmap[bit / Long.SIZE_BITS] or (1L shl (bit % Long.SIZE_BITS))
    }

    private fun shiftLeft(distance: Int) {
        if (distance >= windowSize) {
            bitmap.fill(0L)
            return
        }
        val words = distance / Long.SIZE_BITS
        val bits = distance % Long.SIZE_BITS
        val shifted = LongArray(bitmap.size)
        for (destination in bitmap.indices.reversed()) {
            val source = destination - words
            if (source < 0) continue
            shifted[destination] = bitmap[source] shl bits
            if (bits > 0 && source > 0) {
                shifted[destination] =
                    shifted[destination] or (bitmap[source - 1] ushr (Long.SIZE_BITS - bits))
            }
        }
        shifted.copyInto(bitmap)
    }

    private companion object {
        const val DEFAULT_WINDOW_SIZE = 1024
    }
}
