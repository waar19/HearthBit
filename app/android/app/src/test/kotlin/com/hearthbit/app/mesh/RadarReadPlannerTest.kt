package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RadarReadPlannerTest {
    private fun planner() = RadarReadPlanner(
        unresponsiveAfterStrikes = 3,
        retryUnresponsiveAfterMs = 10_000L,
        maxTentativeReads = 3,
        diagnosticAfterMs = 10_000L,
    )

    @Test
    fun `lee todas las direcciones mapeadas mientras respondan`() {
        val planner = planner()
        planner.start(0L)

        val plan = planner.plan(1_000L, listOf("AA", "BB"), listOf("CC"))

        assertEquals(listOf("AA", "BB"), plan.mapped)
        assertTrue(plan.tentative.isEmpty())
    }

    @Test
    fun `aparta un enlace sin callbacks y lo reintenta espaciado`() {
        val planner = planner()
        planner.start(0L)

        assertFalse(planner.recordReadAttempt("AA", accepted = true, now = 500L))
        assertFalse(planner.recordReadAttempt("AA", accepted = true, now = 1_000L))
        assertTrue(planner.recordReadAttempt("AA", accepted = true, now = 1_500L))

        // Recién marcada: fuera del plan.
        assertTrue(planner.plan(2_000L, listOf("AA"), emptyList()).mapped.isEmpty())
        // Pasado el periodo de gracia vuelve a intentarse una vez...
        assertEquals(
            listOf("AA"),
            planner.plan(12_000L, listOf("AA"), emptyList()).mapped,
        )
        // ...pero inmediatamente después vuelve a esperar.
        assertTrue(planner.plan(12_500L, listOf("AA"), emptyList()).mapped.isEmpty())
    }

    @Test
    fun `una lectura rechazada pesa doble`() {
        val planner = planner()
        planner.start(0L)

        assertFalse(planner.recordReadAttempt("AA", accepted = false, now = 500L))
        assertTrue(planner.recordReadAttempt("AA", accepted = true, now = 1_000L))
    }

    @Test
    fun `un callback exitoso rehabilita el enlace`() {
        val planner = planner()
        planner.start(0L)
        planner.recordReadAttempt("AA", accepted = true, now = 500L)
        planner.recordReadAttempt("AA", accepted = true, now = 1_000L)
        planner.recordReadAttempt("AA", accepted = true, now = 1_500L)
        assertTrue(planner.plan(2_000L, listOf("AA"), emptyList()).mapped.isEmpty())

        planner.recordCallbackSuccess("AA")

        assertEquals(
            listOf("AA"),
            planner.plan(2_500L, listOf("AA"), emptyList()).mapped,
        )
    }

    @Test
    fun `sin mapeados utilizables recurre a tentativas acotadas`() {
        val planner = planner()
        planner.start(0L)

        val sinMapeados = planner.plan(
            1_000L,
            emptyList(),
            listOf("CC", "DD", "EE", "FF"),
        )
        assertEquals(listOf("CC", "DD", "EE"), sinMapeados.tentative)

        // Con un mapeado utilizable no hay tentativas.
        val conMapeado = planner.plan(1_500L, listOf("AA"), listOf("CC"))
        assertEquals(listOf("AA"), conMapeado.mapped)
        assertTrue(conMapeado.tentative.isEmpty())
    }

    @Test
    fun `el diagnostico salta sin muestras y se auto-limita`() {
        val planner = planner()
        planner.start(0L)

        assertFalse(planner.diagnosticDue(5_000L))
        assertTrue(planner.diagnosticDue(10_000L))
        // Se acaba de avisar: no repite en el siguiente ciclo.
        assertFalse(planner.diagnosticDue(10_500L))
        assertTrue(planner.diagnosticDue(20_500L))
    }

    @Test
    fun `una muestra emitida reinicia el temporizador de diagnostico`() {
        val planner = planner()
        planner.start(0L)
        planner.recordSampleEmitted(9_000L)

        assertFalse(planner.diagnosticDue(10_000L))
        assertTrue(planner.diagnosticDue(19_000L))
    }

    @Test
    fun `sin arrancar no emite diagnostico`() {
        val planner = planner()

        assertFalse(planner.diagnosticDue(60_000L))
    }
}
