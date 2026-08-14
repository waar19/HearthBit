package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GenericPresenceScanPolicyTest {
    @Test
    fun `usa diez segundos de escaneo y cincuenta de pausa`() {
        assertEquals(
            10_000L,
            GenericPresenceScanPolicy.durationMs(GenericPresenceScanPhase.SCANNING),
        )
        assertEquals(
            50_000L,
            GenericPresenceScanPolicy.durationMs(GenericPresenceScanPhase.PAUSED),
        )
    }

    @Test
    fun `alterna fases sin depender de perfiles de energia`() {
        PowerProfile.entries.forEach {
            assertEquals(
                GenericPresenceScanPhase.PAUSED,
                GenericPresenceScanPolicy.nextPhase(
                    current = GenericPresenceScanPhase.SCANNING,
                    enabled = true,
                    engineRunning = true,
                ),
            )
            assertEquals(
                GenericPresenceScanPhase.SCANNING,
                GenericPresenceScanPolicy.nextPhase(
                    current = GenericPresenceScanPhase.PAUSED,
                    enabled = true,
                    engineRunning = true,
                ),
            )
        }
    }

    @Test
    fun `no programa otra fase si esta deshabilitado o detenido`() {
        assertNull(
            GenericPresenceScanPolicy.nextPhase(
                current = GenericPresenceScanPhase.SCANNING,
                enabled = false,
                engineRunning = true,
            ),
        )
        assertNull(
            GenericPresenceScanPolicy.nextPhase(
                current = GenericPresenceScanPhase.PAUSED,
                enabled = true,
                engineRunning = false,
            ),
        )
    }
}
