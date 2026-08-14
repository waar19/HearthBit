package com.hearthbit.app.mesh

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.content.Context
import android.os.Build
import android.ranging.RangingData
import android.ranging.RangingDevice
import android.ranging.RangingManager
import android.ranging.RangingPreference
import android.ranging.RangingSession
import android.ranging.oob.DeviceHandle
import android.ranging.oob.OobInitiatorRangingConfig
import android.ranging.oob.OobResponderRangingConfig
import android.ranging.oob.TransportHandle
import androidx.annotation.RequiresApi
import java.time.Duration
import java.util.concurrent.Executor

internal class RadioRangingManager(
    private val context: Context,
    private val sendControl: (String, ByteArray) -> Unit,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private var active: ActiveSession? = null
    private var capabilities: Map<String, Boolean> = emptyMap()

    fun isAvailable(): Boolean = Build.VERSION.SDK_INT >= 36

    fun capabilitiesSnapshot(): Map<String, Any> = mapOf(
        "available" to isAvailable(),
        "bluetoothChannelSounding" to (capabilities["bluetoothChannelSounding"] == true),
        "wifiNanRtt" to (capabilities["wifiNanRtt"] == true),
        "bleRssi" to (capabilities["bleRssi"] == true),
    )

    fun registerCapabilities() {
        if (Build.VERSION.SDK_INT >= 36) Api36.registerCapabilities(this)
    }

    fun startInitiator(peerId: String, bluetoothDevice: BluetoothDevice?) {
        check(Build.VERSION.SDK_INT >= 36) { "Radio ranging requires Android 16" }
        stop()
        val nonce = RangingControlProtocol.randomNonce()
        sendControl(
            peerId,
            RangingControlProtocol.encode(
                RangingControlProtocol.Control(
                    action = RangingControlProtocol.ACTION_REQUEST,
                    technology = preferredTechnology(),
                    sessionNonce = nonce,
                    round = 0,
                    value = 0.0,
                    errorMeters = 0f,
                    confidence = 0f,
                    opaqueData = byteArrayOf(),
                ),
            ),
        )
        Api36.start(this, peerId, nonce, bluetoothDevice, initiator = true)
    }

    fun acceptRequest(
        peerId: String,
        control: RangingControlProtocol.Control,
        bluetoothDevice: BluetoothDevice?,
    ) {
        if (Build.VERSION.SDK_INT < 36 || control.action != RangingControlProtocol.ACTION_REQUEST) {
            return
        }
        stop()
        sendControl(
            peerId,
            RangingControlProtocol.encode(
                control.copy(action = RangingControlProtocol.ACTION_ACCEPT),
            ),
        )
        Api36.start(this, peerId, control.sessionNonce, bluetoothDevice, initiator = false)
    }

    fun receiveOob(peerId: String, control: RangingControlProtocol.Control) {
        if (control.action != RangingControlProtocol.ACTION_OOB_DATA) return
        val current = active ?: return
        if (current.peerId == peerId &&
            current.nonce.contentEquals(control.sessionNonce)
        ) {
            current.transport.receive(control.opaqueData)
        }
    }

    fun stop() {
        if (Build.VERSION.SDK_INT >= 36) Api36.stop(this)
    }

    private fun preferredTechnology(): Byte = when {
        capabilities["bluetoothChannelSounding"] == true ->
            RangingControlProtocol.TECHNOLOGY_BLE_CS
        capabilities["wifiNanRtt"] == true ->
            RangingControlProtocol.TECHNOLOGY_WIFI_NAN_RTT
        else -> RangingControlProtocol.TECHNOLOGY_BLE_RSSI
    }

    @RequiresApi(36)
    private data class ActiveSession(
        val peerId: String,
        val nonce: ByteArray,
        val session: RangingSession,
        val transport: MeshTransportHandle,
    )

    @RequiresApi(36)
    private class MeshTransportHandle(
        private val peerId: String,
        private val nonce: ByteArray,
        private val sendControl: (String, ByteArray) -> Unit,
    ) : TransportHandle {
        private var executor: Executor? = null
        private var callback: TransportHandle.ReceiveCallback? = null

        override fun sendData(data: ByteArray) {
            runCatching {
                sendControl(
                    peerId,
                    RangingControlProtocol.encode(
                        RangingControlProtocol.Control(
                            action = RangingControlProtocol.ACTION_OOB_DATA,
                            technology = RangingControlProtocol.TECHNOLOGY_NONE,
                            sessionNonce = nonce,
                            round = 0,
                            value = 0.0,
                            errorMeters = 0f,
                            confidence = 0f,
                            opaqueData = data,
                        ),
                    ),
                )
            }.onFailure {
                executor?.execute { callback?.onSendFailed() }
            }
        }

        override fun registerReceiveCallback(
            executor: Executor,
            callback: TransportHandle.ReceiveCallback,
        ) {
            this.executor = executor
            this.callback = callback
        }

        fun receive(data: ByteArray) {
            executor?.execute { callback?.onReceiveData(data) }
        }

        override fun close() {
            executor?.execute { callback?.onClose() }
            callback = null
            executor = null
        }
    }

    @RequiresApi(36)
    private object Api36 {
        private var capabilitiesCallback: RangingManager.RangingCapabilitiesCallback? = null

        fun registerCapabilities(owner: RadioRangingManager) {
            val manager = owner.context.getSystemService(RangingManager::class.java)
            capabilitiesCallback?.let(manager::unregisterCapabilitiesCallback)
            capabilitiesCallback = RangingManager.RangingCapabilitiesCallback { value ->
                owner.capabilities = mapOf(
                    "bluetoothChannelSounding" to (value.csCapabilities != null),
                    "wifiNanRtt" to (value.rttRangingCapabilities != null),
                    "bleRssi" to value.technologyAvailability.containsKey(RangingManager.BLE_RSSI),
                )
                owner.emit(
                    mapOf(
                        "type" to "rangingCapabilities",
                        "capabilities" to owner.capabilitiesSnapshot(),
                    ),
                )
            }.also { callback ->
                manager.registerCapabilitiesCallback(owner.context.mainExecutor, callback)
            }
        }

        @SuppressLint("MissingPermission")
        fun start(
            owner: RadioRangingManager,
            peerId: String,
            nonce: ByteArray,
            bluetoothDevice: BluetoothDevice?,
            initiator: Boolean,
        ) {
            val manager = owner.context.getSystemService(RangingManager::class.java)
            val transport = MeshTransportHandle(peerId, nonce, owner.sendControl)
            val rangingDevice = RangingDevice.Builder().build()
            val deviceBuilder = DeviceHandle.Builder(rangingDevice, transport)
            if (Build.VERSION.SDK_INT >= 37 && bluetoothDevice != null) {
                // El módulo relay aún compila contra API 36. La API 37 añade
                // setBluetoothDevice; reflexión conserva ese build y activa
                // Channel Sounding cuando el SO nuevo expone el método.
                runCatching {
                    deviceBuilder.javaClass
                        .getMethod("setBluetoothDevice", BluetoothDevice::class.java)
                        .invoke(deviceBuilder, bluetoothDevice)
                }
            }
            val deviceHandle = deviceBuilder.build()
            val callback = object : RangingSession.Callback {
                override fun onOpened() {
                    owner.emit(mapOf("type" to "radioRangingState", "state" to "opened"))
                }

                override fun onOpenFailed(reason: Int) {
                    owner.emit(
                        mapOf(
                            "type" to "radioRangingState",
                            "state" to "error",
                            "reason" to reason,
                        ),
                    )
                }

                override fun onStarted(peer: RangingDevice, technology: Int) {
                    owner.emit(
                        mapOf(
                            "type" to "radioRangingState",
                            "state" to "active",
                            "technology" to technology,
                        ),
                    )
                }

                override fun onStopped(peer: RangingDevice, technology: Int) {
                    owner.emit(mapOf("type" to "radioRangingState", "state" to "stopped"))
                }

                override fun onClosed(reason: Int) {
                    owner.emit(mapOf("type" to "radioRangingState", "state" to "closed"))
                }

                override fun onResults(peer: RangingDevice, data: RangingData) {
                    val measurement = data.distance ?: return
                    val confidence = (measurement.confidence / 100f).coerceIn(0f, 1f)
                    owner.emit(
                        mapOf(
                            "type" to "rangingMeasurement",
                            "peerId" to peerId,
                            "meters" to measurement.measurement,
                            "errorMeters" to
                                (measurement.measurement * (1 - confidence)).coerceAtLeast(0.1),
                            "confidence" to confidence,
                            "technology" to data.rangingTechnology,
                        ),
                    )
                }
            }
            val session = manager.createRangingSession(owner.context.mainExecutor, callback)
                ?: run {
                    owner.emit(
                        mapOf(
                            "type" to "radioRangingState",
                            "state" to "unavailable",
                        ),
                    )
                    transport.close()
                    return
                }
            owner.active = ActiveSession(peerId, nonce, session, transport)
            val preference = if (initiator) {
                val config = OobInitiatorRangingConfig.Builder()
                    .setFastestRangingInterval(Duration.ofMillis(250))
                    .setSlowestRangingInterval(Duration.ofSeconds(2))
                    .setRangingMode(OobInitiatorRangingConfig.RANGING_MODE_AUTO)
                    .setSecurityLevel(OobInitiatorRangingConfig.SECURITY_LEVEL_BASIC)
                    .addDeviceHandle(deviceHandle)
                    .build()
                RangingPreference.Builder(RangingPreference.DEVICE_ROLE_INITIATOR, config).build()
            } else {
                val config = OobResponderRangingConfig.Builder(deviceHandle).build()
                RangingPreference.Builder(RangingPreference.DEVICE_ROLE_RESPONDER, config).build()
            }
            session.start(preference)
        }

        fun stop(owner: RadioRangingManager) {
            owner.active?.let {
                runCatching { it.session.stop() }
                runCatching { it.transport.close() }
            }
            owner.active = null
        }
    }
}
