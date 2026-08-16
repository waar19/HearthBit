package com.hearthbit.app.transfer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class WifiDirectTransferTest {
    @Test
    fun `token de rendezvous es estable y separado por transferencia`() {
        val first = WifiDirectTransferSecrets.rendezvousToken("00112233445566778899aabbccddeeff")
        val same = WifiDirectTransferSecrets.rendezvousToken("00112233445566778899aabbccddeeff")
        val other = WifiDirectTransferSecrets.rendezvousToken("ffeeddccbbaa99887766554433221100")

        assertEquals(24, first.length)
        assertEquals(first, same)
        assertNotEquals(first, other)
        assertThrows(IllegalArgumentException::class.java) {
            WifiDirectTransferSecrets.rendezvousToken("")
        }
    }

    @Test
    fun `limita contenedores al maximo de transferencia`() {
        assertFalse(WifiDirectTransferPolicy.isValidContainerSize(0))
        assertTrue(WifiDirectTransferPolicy.isValidContainerSize(1))
        assertTrue(
            WifiDirectTransferPolicy.isValidContainerSize(
                WifiDirectTransferPolicy.MAXIMUM_CONTAINER_BYTES,
            ),
        )
        assertFalse(
            WifiDirectTransferPolicy.isValidContainerSize(
                WifiDirectTransferPolicy.MAXIMUM_CONTAINER_BYTES + 1,
            ),
        )
    }
}
