package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MeshScanHealthPolicyTest {
    @Test
    fun `inicia cuando el escaneo continuo deberia estar activo`() {
        assertEquals(
            MeshScanHealthAction.START,
            MeshScanHealthPolicy.actionFor(
                shouldScanContinuously = true,
                isScanning = false,
                now = 10_000L,
                scanStartedAt = 0L,
                lastResultAt = 0L,
                expectsKnownPeer = false,
            ),
        )
    }

    @Test
    fun `recicla el escaneo antes de la degradacion de Android`() {
        assertEquals(
            MeshScanHealthAction.RESTART,
            MeshScanHealthPolicy.actionFor(
                shouldScanContinuously = true,
                isScanning = true,
                now = MeshScanHealthPolicy.CONTINUOUS_SCAN_CYCLE_MS + 1L,
                scanStartedAt = 1L,
                lastResultAt = 10_000L,
                expectsKnownPeer = false,
            ),
        )
    }

    @Test
    fun `reinicia un escaneo sin resultados durante reconexion conocida`() {
        assertEquals(
            MeshScanHealthAction.RESTART,
            MeshScanHealthPolicy.actionFor(
                shouldScanContinuously = true,
                isScanning = true,
                now = MeshScanHealthPolicy.STALE_SCAN_RESULT_MS + 10_000L,
                scanStartedAt = 1L,
                lastResultAt = 10_000L,
                expectsKnownPeer = true,
            ),
        )
    }

    @Test
    fun `no altera las pausas de perfiles por ciclos`() {
        assertEquals(
            MeshScanHealthAction.NONE,
            MeshScanHealthPolicy.actionFor(
                shouldScanContinuously = false,
                isScanning = false,
                now = Long.MAX_VALUE,
                scanStartedAt = 0L,
                lastResultAt = 0L,
                expectsKnownPeer = true,
            ),
        )
    }

    @Test
    fun `keepalive depende de enlace y perfil`() {
        assertNull(MeshKeepAlivePolicy.intervalMs(PowerProfile.BALANCED, hasActiveLink = false))
        assertEquals(
            30_000L,
            MeshKeepAlivePolicy.intervalMs(PowerProfile.BALANCED, hasActiveLink = true),
        )
        assertEquals(
            90_000L,
            MeshKeepAlivePolicy.intervalMs(PowerProfile.CRITICAL, hasActiveLink = true),
        )
    }
}
