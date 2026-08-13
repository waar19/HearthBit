package com.hearthbit.app.mesh

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdaptivePowerPolicyTest {
    @Test
    fun `battery below twenty percent enables saving`() {
        assertTrue(AdaptivePowerPolicy.shouldSavePower(19))
        assertTrue(AdaptivePowerPolicy.shouldSavePower(0))
    }

    @Test
    fun `twenty percent and above keeps full mesh`() {
        assertFalse(AdaptivePowerPolicy.shouldSavePower(20))
        assertFalse(AdaptivePowerPolicy.shouldSavePower(100))
    }
}
