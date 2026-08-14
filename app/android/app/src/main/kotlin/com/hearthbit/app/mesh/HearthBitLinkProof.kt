package com.hearthbit.app.mesh

internal object HearthBitLinkProof {
    private val value = "HB-LINK1".toByteArray(Charsets.US_ASCII)

    fun bytes(): ByteArray = value.copyOf()

    fun matches(candidate: ByteArray): Boolean = value.contentEquals(candidate)
}
