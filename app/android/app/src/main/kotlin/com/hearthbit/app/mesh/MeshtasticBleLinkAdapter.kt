package com.hearthbit.app.mesh

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger

/**
 * Enlace opcional a un nodo Meshtastic mediante su Device API BLE oficial.
 *
 * El nodo LoRa transporta frames HearthBit opacos en PRIVATE_APP. El usuario
 * debe habilitar explícitamente el enlace; nunca se conecta por defecto a
 * radios cercanas.
 */
@SuppressLint("MissingPermission")
@Suppress("DEPRECATION")
internal class MeshtasticBleLinkAdapter(
    private val context: Context,
    private val onFrame: (frame: ByteArray, sourceAddress: String) -> Unit,
    private val onState: (ready: Boolean, deviceName: String?) -> Unit,
) : LinkAdapter {
    private val adapter: BluetoothAdapter? =
        context.getSystemService(BluetoothManager::class.java)?.adapter
    private val handler = Handler(Looper.getMainLooper())
    private val writeQueue = MeshtasticDeliveryQueue(MAX_QUEUED_WRITES)
    private val packetIds = AtomicInteger((System.currentTimeMillis() and 0x7fffffff).toInt())
    private val droppedWrites = AtomicInteger(0)

    @Volatile
    private var gatt: BluetoothGatt? = null

    @Volatile
    private var toRadio: BluetoothGattCharacteristic? = null

    @Volatile
    private var fromRadio: BluetoothGattCharacteristic? = null

    @Volatile
    private var writing = false

    @Volatile
    private var scanning = false

    @Volatile
    private var desired = false

    @Volatile
    var isReady: Boolean = false
        private set

    @Volatile
    private var connectedAddress: String? = null

    override val capabilities: LinkCapabilities
        get() = LinkCapabilities(
            id = "lora-meshtastic:${connectedAddress ?: "pending"}",
            kind = LinkKind.LORA,
            mtu = MeshtasticFrameCodec.MAX_HEARTHBIT_FRAME_BYTES,
            broadcast = true,
            unicast = false,
            reliability = LinkReliability.ACKNOWLEDGED,
            background = true,
            maxConnections = 1,
            cost = LINK_COST,
        )

    fun start() {
        desired = true
        if (isReady || scanning || gatt != null) return
        val scanner = adapter?.bluetoothLeScanner ?: run {
            onState(false, null)
            return
        }
        scanning = true
        scanner.startScan(
            listOf(
                ScanFilter.Builder()
                    .setServiceUuid(ParcelUuid(MESHTASTIC_SERVICE_UUID))
                    .build(),
            ),
            ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build(),
            scanCallback,
        )
    }

    fun stop() {
        desired = false
        handler.removeCallbacksAndMessages(null)
        stopScan()
        resetConnection()
    }

    private fun resetConnection() {
        setReady(false, null)
        writeQueue.clear()
        writing = false
        toRadio = null
        fromRadio = null
        connectedAddress = null
        runCatching { gatt?.disconnect() }
        runCatching { gatt?.close() }
        gatt = null
    }

    private fun reconnectLater() {
        resetConnection()
        if (!desired) return
        handler.postDelayed(
            { if (desired) start() },
            RECONNECT_DELAY_MS,
        )
    }

    override fun send(frame: ByteArray, priority: LinkPriority): Boolean {
        if (!isReady || frame.isEmpty() || frame.size > capabilities.mtu) return false
        val nextId = packetIds.updateAndGet { current ->
            if (current == Int.MAX_VALUE) 1 else current + 1
        }
        val encoded = runCatching {
            MeshtasticFrameCodec.encodeFrame(
                frame = frame,
                packetId = nextId,
                requestAck = priority == LinkPriority.CRITICAL,
            )
        }.getOrNull() ?: return false
        if (!enqueueWrite(encoded, priority)) return false
        drainWrites()
        return true
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            if (gatt != null) return
            stopScan()
            connectedAddress = result.device.address
            gatt = result.device.connectGatt(
                context,
                false,
                gattCallback,
                BluetoothDevice.TRANSPORT_LE,
            )
        }

        override fun onScanFailed(errorCode: Int) {
            scanning = false
            Log.w(LOG_TAG, "Meshtastic BLE scan failed: $errorCode")
            onState(false, null)
            if (desired) {
                handler.postDelayed(
                    { if (desired) start() },
                    RECONNECT_DELAY_MS,
                )
            }
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS &&
                newState == BluetoothProfile.STATE_CONNECTED
            ) {
                connectedAddress = gatt.device.address
                gatt.requestMtu(RECOMMENDED_MTU)
                gatt.discoverServices()
                return
            }
            if (newState == BluetoothProfile.STATE_DISCONNECTED || status != BluetoothGatt.GATT_SUCCESS) {
                Log.w(LOG_TAG, "Meshtastic BLE disconnected: status=$status")
                reconnectLater()
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                reconnectLater()
                return
            }
            val service = gatt.getService(MESHTASTIC_SERVICE_UUID) ?: run {
                reconnectLater()
                return
            }
            toRadio = service.getCharacteristic(TO_RADIO_UUID)
            fromRadio = service.getCharacteristic(FROM_RADIO_UUID)
            val fromNum = service.getCharacteristic(FROM_NUM_UUID)
            if (toRadio == null || fromRadio == null || fromNum == null) {
                reconnectLater()
                return
            }
            gatt.setCharacteristicNotification(fromNum, true)
            val cccd = fromNum.getDescriptor(CCCD_UUID)
            if (cccd == null) {
                finishSetup(gatt)
                return
            }
            cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            if (!gatt.writeDescriptor(cccd)) reconnectLater()
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            if (descriptor.uuid != CCCD_UUID) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                finishSetup(gatt)
            } else {
                reconnectLater()
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            if (characteristic.uuid == FROM_NUM_UUID) readNext(gatt)
        }

        override fun onCharacteristicRead(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (characteristic.uuid != FROM_RADIO_UUID ||
                status != BluetoothGatt.GATT_SUCCESS
            ) {
                return
            }
            val value = characteristic.value ?: return
            if (value.isEmpty()) return
            MeshtasticFrameCodec.decodeFrame(value)?.let { frame ->
                onFrame(frame, gatt.device.address)
            }
            readNext(gatt)
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (characteristic.uuid != TO_RADIO_UUID) return
            writing = false
            if (status != BluetoothGatt.GATT_SUCCESS) {
                Log.w(LOG_TAG, "Meshtastic ToRadio write failed: $status")
            }
            drainWrites()
        }
    }

    private fun finishSetup(gatt: BluetoothGatt) {
        setReady(true, gatt.device.name)
        enqueueWrite(
            MeshtasticFrameCodec.configRequest(nextConfigNonce()),
            LinkPriority.CRITICAL,
        )
        drainWrites()
        readNext(gatt)
    }

    private fun readNext(gatt: BluetoothGatt) {
        fromRadio?.let { gatt.readCharacteristic(it) }
    }

    @Synchronized
    private fun drainWrites() {
        if (writing || !isReady) return
        val connection = gatt ?: return
        val characteristic = toRadio ?: return
        val bytes = writeQueue.poll() ?: return
        characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        characteristic.value = bytes
        writing = connection.writeCharacteristic(characteristic)
        if (!writing) {
            Log.w(LOG_TAG, "Meshtastic ToRadio write was rejected")
        }
    }

    private fun enqueueWrite(bytes: ByteArray, priority: LinkPriority): Boolean {
        return when (writeQueue.offer(bytes, priority)) {
            MeshtasticQueueOfferResult.ENQUEUED -> true
            MeshtasticQueueOfferResult.EVICTED_STANDARD -> {
                logQueueDrop("Meshtastic BLE queue evicted oldest STANDARD frame")
                true
            }

            MeshtasticQueueOfferResult.REJECTED_FULL -> {
                logQueueDrop("Meshtastic BLE queue rejected $priority frame")
                false
            }
        }
    }

    private fun logQueueDrop(message: String) {
        val count = droppedWrites.updateAndGet { current ->
            if (current == Int.MAX_VALUE) 1 else current + 1
        }
        if (count <= INITIAL_DROP_LOG_LIMIT || count % DROP_LOG_INTERVAL == 0) {
            Log.w(LOG_TAG, "$message (drop count=$count)")
        }
    }

    private fun setReady(ready: Boolean, deviceName: String?) {
        if (isReady == ready) return
        isReady = ready
        onState(ready, deviceName)
    }

    private fun stopScan() {
        if (!scanning) return
        scanning = false
        runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
    }

    private fun nextConfigNonce(): Int =
        packetIds.updateAndGet { current -> if (current == Int.MAX_VALUE) 1 else current + 1 }

    private companion object {
        const val LOG_TAG = "HearthBitMeshtastic"
        const val RECOMMENDED_MTU = 512
        const val LINK_COST = 30
        const val MAX_QUEUED_WRITES = 64
        const val RECONNECT_DELAY_MS = 5_000L
        const val INITIAL_DROP_LOG_LIMIT = 3
        const val DROP_LOG_INTERVAL = 64
        val MESHTASTIC_SERVICE_UUID: UUID =
            UUID.fromString("6ba1b218-15a8-461f-9fa8-5dcae273eafd")
        val FROM_RADIO_UUID: UUID =
            UUID.fromString("2c55e69e-4993-11ed-b878-0242ac120002")
        val TO_RADIO_UUID: UUID =
            UUID.fromString("f75c76d2-129e-4dad-a1dd-7866124401e7")
        val FROM_NUM_UUID: UUID =
            UUID.fromString("ed9da18c-a800-4f66-a670-aa7547e34453")
        val CCCD_UUID: UUID =
            UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
