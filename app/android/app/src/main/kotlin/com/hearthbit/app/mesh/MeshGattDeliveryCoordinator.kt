package com.hearthbit.app.mesh

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothStatusCodes
import android.os.Build
import android.os.Handler

internal class MeshGattDeliveryCoordinator(
    private val mainHandler: Handler,
    private val maxPendingWrites: Int = MeshEngineConstants.MAX_PENDING_GATT_WRITES,
    private val onDeliveryFailure: (
        transport: String,
        address: String,
        critical: Boolean,
        attempts: Int,
        reason: String,
    ) -> Unit,
    private val isClientLinkActive: (address: String, gatt: BluetoothGatt) -> Boolean,
    private val isClientReady: (address: String) -> Boolean,
    private val isServerLinkActive: (server: BluetoothGattServer, device: BluetoothDevice) -> Boolean,
) {
    private val clientWriteLock = Any()
    private val clientWriteQueues = mutableMapOf<String, GattDeliveryQueue>()
    private val clientWritesInFlight = mutableSetOf<String>()
    private val clientWriteOwners = mutableMapOf<String, BluetoothGatt>()

    private val serverNotificationLock = Any()
    private val serverNotificationQueues = mutableMapOf<String, GattDeliveryQueue>()
    private val serverNotificationsInFlight = mutableSetOf<String>()

    @SuppressLint("MissingPermission")
    fun enqueueClientWrites(
        address: String,
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        frames: List<ByteArray>,
        critical: Boolean,
    ): Boolean {
        if (frames.isEmpty()) return true
        if (!isClientLinkActive(address, gatt)) return false
        val result = synchronized(clientWriteLock) {
            if (!isClientLinkActive(address, gatt)) return false
            if (clientWriteOwners[address] !== gatt) {
                clientWriteQueues.remove(address)
                clientWritesInFlight.remove(address)
                clientWriteOwners[address] = gatt
            }
            val queue = clientWriteQueues.getOrPut(address) {
                GattDeliveryQueue(maxPendingWrites)
            }
            val accepted = queue.enqueue(frames, critical)
            accepted to (
                accepted &&
                    isClientReady(address) &&
                    clientWritesInFlight.add(address)
                )
        }
        if (!result.first) {
            onDeliveryFailure("client", address, critical, 0, "queueFull")
            return false
        }
        if (result.second) writeNextClient(address, gatt, characteristic)
        return true
    }

    @SuppressLint("MissingPermission")
    fun writeNextClient(
        address: String,
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ) {
        val next = synchronized(clientWriteLock) {
            if (!isClientLinkActive(address, gatt) || clientWriteOwners[address] !== gatt) return
            clientWriteQueues[address]?.next()?.bytes
        }
        if (next == null) {
            synchronized(clientWriteLock) {
                if (clientWriteOwners[address] === gatt) {
                    clientWritesInFlight.remove(address)
                    clientWriteOwners.remove(address)
                }
            }
            return
        }
        val accepted = runCatching {
            if (Build.VERSION.SDK_INT >= 33) {
                gatt.writeCharacteristic(
                    characteristic,
                    next,
                    BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
                ) == BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                @Suppress("DEPRECATION")
                characteristic.value = next
                @Suppress("DEPRECATION")
                gatt.writeCharacteristic(characteristic)
            }
        }.getOrDefault(false)
        if (!accepted) {
            handleClientWriteResult(
                address,
                gatt,
                characteristic,
                success = false,
                reason = "writeRejected",
            )
        }
    }

    fun handleClientWriteResult(
        address: String,
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        success: Boolean,
        reason: String,
    ) {
        if (!isClientLinkActive(address, gatt)) return
        val outcome = synchronized(clientWriteLock) {
            if (clientWriteOwners[address] !== gatt) return
            val queue = clientWriteQueues[address] ?: return
            queue.complete(success).also {
                if (queue.size == 0) clientWriteQueues.remove(address)
            }
        }
        when (outcome) {
            GattDeliveryOutcome.Advance -> writeNextClient(address, gatt, characteristic)
            is GattDeliveryOutcome.Retry -> mainHandler.postDelayed(
                {
                    if (isClientLinkActive(address, gatt) && isClientReady(address)) {
                        writeNextClient(address, gatt, characteristic)
                    }
                },
                outcome.delayMs,
            )
            is GattDeliveryOutcome.Failed -> {
                onDeliveryFailure(
                    "client",
                    address,
                    outcome.frame.critical,
                    outcome.frame.failedAttempts,
                    reason,
                )
                writeNextClient(address, gatt, characteristic)
            }
        }
    }

    fun clearClientDeliveryState(address: String, expectedGatt: BluetoothGatt? = null) {
        synchronized(clientWriteLock) {
            val owner = clientWriteOwners[address]
            if (expectedGatt != null && owner != null && owner !== expectedGatt) return
            clientWriteQueues.remove(address)
            clientWritesInFlight.remove(address)
            clientWriteOwners.remove(address)
        }
    }

    fun clearAllClientDeliveryState() {
        synchronized(clientWriteLock) {
            clientWriteQueues.clear()
            clientWritesInFlight.clear()
            clientWriteOwners.clear()
        }
    }

    fun hasPendingClientWrites(address: String): Boolean =
        synchronized(clientWriteLock) {
            clientWriteQueues[address]?.size?.let { it > 0 } == true
        }

    fun markClientWritesInFlight(address: String): Boolean =
        synchronized(clientWriteLock) { clientWritesInFlight.add(address) }

    @SuppressLint("MissingPermission")
    fun enqueueServerNotifications(
        device: BluetoothDevice,
        server: BluetoothGattServer,
        characteristic: BluetoothGattCharacteristic,
        frames: List<ByteArray>,
        critical: Boolean,
    ): Boolean {
        if (frames.isEmpty()) return true
        val address = device.address
        if (!isServerLinkActive(server, device)) return false
        val result = synchronized(serverNotificationLock) {
            if (!isServerLinkActive(server, device)) return false
            val queue = serverNotificationQueues.getOrPut(address) {
                GattDeliveryQueue(maxPendingWrites)
            }
            val accepted = queue.enqueue(frames, critical)
            accepted to (accepted && serverNotificationsInFlight.add(address))
        }
        if (!result.first) {
            onDeliveryFailure("server", address, critical, 0, "queueFull")
            return false
        }
        if (result.second) writeNextServerNotification(device, server, characteristic)
        return true
    }

    @SuppressLint("MissingPermission")
    fun writeNextServerNotification(
        device: BluetoothDevice,
        server: BluetoothGattServer,
        characteristic: BluetoothGattCharacteristic,
    ) {
        val address = device.address
        if (!isServerLinkActive(server, device)) {
            clearServerDeliveryState(address)
            return
        }
        val next = synchronized(serverNotificationLock) {
            serverNotificationQueues[address]?.next()?.bytes
        }
        if (next == null) {
            synchronized(serverNotificationLock) { serverNotificationsInFlight.remove(address) }
            return
        }
        val accepted = runCatching {
            if (Build.VERSION.SDK_INT >= 33) {
                server.notifyCharacteristicChanged(device, characteristic, false, next) ==
                    BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                characteristic.value = next
                @Suppress("DEPRECATION")
                server.notifyCharacteristicChanged(device, characteristic, false)
            }
        }.getOrDefault(false)
        if (!accepted) {
            handleServerNotificationResult(
                device,
                server,
                characteristic,
                success = false,
                reason = "notifyRejected",
            )
        }
    }

    fun handleServerNotificationResult(
        device: BluetoothDevice,
        server: BluetoothGattServer,
        characteristic: BluetoothGattCharacteristic,
        success: Boolean,
        reason: String,
    ) {
        val address = device.address
        val outcome = synchronized(serverNotificationLock) {
            val queue = serverNotificationQueues[address] ?: return
            queue.complete(success).also {
                if (queue.size == 0) serverNotificationQueues.remove(address)
            }
        }
        when (outcome) {
            GattDeliveryOutcome.Advance ->
                writeNextServerNotification(device, server, characteristic)
            is GattDeliveryOutcome.Retry -> mainHandler.postDelayed(
                {
                    if (isServerLinkActive(server, device)) {
                        writeNextServerNotification(device, server, characteristic)
                    } else {
                        synchronized(serverNotificationLock) {
                            serverNotificationsInFlight.remove(address)
                        }
                    }
                },
                outcome.delayMs,
            )
            is GattDeliveryOutcome.Failed -> {
                onDeliveryFailure(
                    "server",
                    address,
                    outcome.frame.critical,
                    outcome.frame.failedAttempts,
                    reason,
                )
                writeNextServerNotification(device, server, characteristic)
            }
        }
    }

    fun clearServerDeliveryState(address: String) {
        synchronized(serverNotificationLock) {
            serverNotificationQueues.remove(address)
            serverNotificationsInFlight.remove(address)
        }
    }

    fun clearAllServerDeliveryState() {
        synchronized(serverNotificationLock) {
            serverNotificationQueues.clear()
            serverNotificationsInFlight.clear()
        }
    }
}
