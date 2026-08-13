package com.hearthbit.app.mesh

import org.junit.Assert.assertEquals
import org.junit.Test

class MeshNotificationStateReducerTest {
    @Test
    fun `reduce inicio actividad y error a contenido visible`() {
        assertEquals(
            MeshNotificationContent.STARTING,
            MeshNotificationStateReducer.contentFor(MeshNotificationState("starting", 0)),
        )
        assertEquals(
            MeshNotificationContent.ACTIVE,
            MeshNotificationStateReducer.contentFor(MeshNotificationState("active", 2)),
        )
        assertEquals(
            MeshNotificationContent.ERROR,
            MeshNotificationStateReducer.contentFor(
                MeshNotificationState("active", 2, "scan failed"),
            ),
        )
    }
}
