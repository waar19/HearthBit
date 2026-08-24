package com.hearthbit.app.mesh

import android.bluetooth.BluetoothGatt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AnchorOtaPriorityCoordinatorTest {
    @Test
    fun `request high before manifest and restore balanced on every terminal state`() {
        val calls = mutableListOf<Int>()
        val coord = AnchorOtaPriorityCoordinator { priority ->
            calls.add(priority)
            true
        }

        // startAnchorOta -> OTA_MANIFEST
        coord.requestHigh()
        // resendAnchorOtaManifest -> OTA_MANIFEST (mismo peer)
        coord.requestHigh()
        // processAnchorOtaPacket (OTA_STATUS = 0)
        coord.restoreBalanced()
        // confirmAnchorOta
        coord.restoreBalanced()
        // failAnchorOtaLocked
        coord.restoreBalanced()

        assertEquals(
            listOf(
                BluetoothGatt.CONNECTION_PRIORITY_HIGH,
                BluetoothGatt.CONNECTION_PRIORITY_HIGH,
                BluetoothGatt.CONNECTION_PRIORITY_BALANCED,
                BluetoothGatt.CONNECTION_PRIORITY_BALANCED,
                BluetoothGatt.CONNECTION_PRIORITY_BALANCED,
            ),
            calls,
        )
    }

    @Test
    fun `restore balanced is idempotent and tolerates repeated calls`() {
        val calls = mutableListOf<Int>()
        val coord = AnchorOtaPriorityCoordinator { priority ->
            calls.add(priority)
            true
        }

        coord.restoreBalanced()
        coord.restoreBalanced()
        coord.restoreBalanced()

        assertEquals(3, calls.size)
        assertTrue(calls.all { it == BluetoothGatt.CONNECTION_PRIORITY_BALANCED })
    }

    @Test
    fun `apply failures do not abort the OTA at the coordinator level`() {
        val calls = mutableListOf<Int>()
        val coord = AnchorOtaPriorityCoordinator { priority ->
            calls.add(priority)
            // Sin GATT cliente (peer no conectado o controlador sin API) el
            // apply reporta false; la OTA debe continuar.
            false
        }

        coord.requestHigh()
        coord.restoreBalanced()

        assertEquals(
            listOf(
                BluetoothGatt.CONNECTION_PRIORITY_HIGH,
                BluetoothGatt.CONNECTION_PRIORITY_BALANCED,
            ),
            calls,
        )
    }
}
