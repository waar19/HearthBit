package com.hearthbit.app.mesh

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.NetworkInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

internal object WifiDirectMeshPolicy {
    const val AUTONOMOUS_GROUP_DELAY_MS = 5_000L

    fun shouldRun(rescueActive: Boolean, degraded: Boolean): Boolean =
        rescueActive || degraded

    fun shouldCreateAutonomousGroup(
        rescueActive: Boolean,
        connected: Boolean,
        discoveredPeers: Int,
    ): Boolean = rescueActive && !connected && discoveredPeers == 0
}

internal data class WifiDirectMeshState(
    val available: Boolean,
    val active: Boolean,
    val connected: Boolean,
    val groupOwner: Boolean = false,
    val groupOwnerAddress: String? = null,
    val reason: String? = null,
)

internal object WifiDirectEmergencyFraming {
    const val MAXIMUM_FRAME_SIZE = 2_048
    private const val HELLO_SIZE = 25
    private val MAGIC = byteArrayOf(0x48, 0x42, 0x45, 0x4D)

    fun buildHello(gatewayId: ByteArray, maximumFrameSize: Int = MAXIMUM_FRAME_SIZE): ByteArray {
        require(gatewayId.size == 16)
        require(maximumFrameSize in 1..65_535)
        return ByteArray(HELLO_SIZE).also { output ->
            MAGIC.copyInto(output)
            output[4] = 1
            gatewayId.copyInto(output, destinationOffset = 5)
            output[21] = (maximumFrameSize ushr 24).toByte()
            output[22] = (maximumFrameSize ushr 16).toByte()
            output[23] = (maximumFrameSize ushr 8).toByte()
            output[24] = maximumFrameSize.toByte()
        }
    }

    fun parseMaximumFrameSize(hello: ByteArray): Int {
        require(hello.size == HELLO_SIZE && hello.copyOfRange(0, 4).contentEquals(MAGIC))
        require(hello[4].toInt() == 1)
        return (
            ((hello[21].toInt() and 0xff) shl 24) or
                ((hello[22].toInt() and 0xff) shl 16) or
                ((hello[23].toInt() and 0xff) shl 8) or
                (hello[24].toInt() and 0xff)
            ).also { require(it in 1..65_535) }
    }
}

/**
 * Establece el enlace Wi-Fi Direct y transporta frames de emergencia mediante
 * el mismo framing abierto de LAN. La firma se valida en [MeshEngine] antes de
 * aceptar el frame en la malla.
 */
internal class WifiDirectMeshTransport(
    context: Context,
    private val onState: (WifiDirectMeshState) -> Unit,
    private val onEmergencyFrame: (ByteArray) -> Unit,
) {
    private val appContext = context.applicationContext
    private val manager =
        appContext.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
    private var channel = manager?.initialize(appContext, Looper.getMainLooper(), null)
    private val handler = Handler(Looper.getMainLooper())
    private val discoveredDevices = ConcurrentHashMap.newKeySet<String>()
    private var serviceRequest: WifiP2pDnsSdServiceRequest? = null
    private var localService: WifiP2pDnsSdServiceInfo? = null
    private var receiverRegistered = false
    private var active = false
    private var rescueActive = false
    private var connected = false
    private var groupConnected = false
    private var autonomousGroupTask: Runnable? = null
    private val instanceName = "$SERVICE_INSTANCE_PREFIX${UUID.randomUUID().toString().take(8)}"
    private val gatewayId = ByteArray(16).also(SecureRandom()::nextBytes)
    private val ioExecutor = Executors.newCachedThreadPool()
    private val socketLock = Any()
    private val ingressTimes = ArrayDeque<Long>()
    @Volatile
    private var serverSocket: ServerSocket? = null
    @Volatile
    private var emergencySocket: Socket? = null
    @Volatile
    private var emergencyOutput: DataOutputStream? = null
    @Volatile
    private var peerMaximumFrameSize = WifiDirectEmergencyFraming.MAXIMUM_FRAME_SIZE

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val enabled = intent.getIntExtra(
                        WifiP2pManager.EXTRA_WIFI_STATE,
                        WifiP2pManager.WIFI_P2P_STATE_DISABLED,
                    ) == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    if (!enabled) {
                        groupConnected = false
                        connected = false
                        closeSockets()
                        emit(available = false, reason = "wifi_p2p_disabled")
                    }
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    @Suppress("DEPRECATION")
                    val networkInfo =
                        intent.getParcelableExtra<NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
                    groupConnected = networkInfo?.isConnected == true
                    if (groupConnected) {
                        requestConnectionInfo()
                    } else {
                        connected = false
                        closeSockets()
                        emit(available = true)
                    }
                }
                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                    // La dirección del dispositivo no se persiste ni se expone.
                }
            }
        }
    }

    fun isSupported(): Boolean =
        manager != null &&
            appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)

    @SuppressLint("MissingPermission")
    fun start(rescueActive: Boolean) {
        this.rescueActive = rescueActive
        if (active) {
            scheduleAutonomousGroup()
            return
        }
        if (!isSupported() || !hasPermission()) {
            emit(available = false, reason = "wifi_p2p_unavailable_or_permission")
            return
        }
        val actualManager = manager ?: return
        val actualChannel = channel ?: actualManager.initialize(
            appContext,
            Looper.getMainLooper(),
            null,
        ).also { channel = it }
        active = true
        registerReceiver()
        actualManager.setDnsSdResponseListeners(
            actualChannel,
            { instanceName, registrationType, device ->
                if (registrationType.startsWith(SERVICE_TYPE) &&
                    instanceName.startsWith(SERVICE_INSTANCE_PREFIX)
                ) {
                    discoveredDevices.add(device.deviceAddress)
                    connect(device)
                }
            },
            { _, _, device ->
                discoveredDevices.add(device.deviceAddress)
            },
        )
        localService = WifiP2pDnsSdServiceInfo.newInstance(
            instanceName,
            SERVICE_TYPE,
            mapOf(
                "v" to "1",
                "emergencyPort" to WIFI_DIRECT_EMERGENCY_PORT.toString(),
                "secure" to "0",
            ),
        ).also { service ->
            actualManager.addLocalService(actualChannel, service, action("add_local_service"))
        }
        serviceRequest = WifiP2pDnsSdServiceRequest.newInstance().also { request ->
            actualManager.addServiceRequest(actualChannel, request, action("add_service_request"))
        }
        actualManager.discoverServices(actualChannel, action("discover_services"))
        actualManager.discoverPeers(actualChannel, action("discover_peers"))
        scheduleAutonomousGroup()
        emit(available = true)
    }

    @SuppressLint("MissingPermission")
    fun stop() {
        autonomousGroupTask?.let(handler::removeCallbacks)
        autonomousGroupTask = null
        val actualManager = manager
        val actualChannel = channel
        if (actualManager != null && actualChannel != null) {
            serviceRequest?.let { actualManager.removeServiceRequest(actualChannel, it, null) }
            localService?.let { actualManager.removeLocalService(actualChannel, it, null) }
            actualManager.cancelConnect(actualChannel, null)
            actualManager.removeGroup(actualChannel, null)
        }
        serviceRequest = null
        localService = null
        discoveredDevices.clear()
        groupConnected = false
        connected = false
        closeSockets()
        active = false
        rescueActive = false
        if (receiverRegistered) {
            runCatching { appContext.unregisterReceiver(receiver) }
            receiverRegistered = false
        }
        emit(available = isSupported())
    }

    @SuppressLint("MissingPermission")
    private fun connect(device: WifiP2pDevice) {
        if (!active || groupConnected || device.deviceAddress.isBlank()) return
        val actualManager = manager ?: return
        val actualChannel = channel ?: return
        @Suppress("DEPRECATION")
        val config = WifiP2pConfig().apply {
            deviceAddress = device.deviceAddress
            groupOwnerIntent = if (rescueActive) 15 else 7
        }
        actualManager.connect(actualChannel, config, action("connect"))
    }

    @SuppressLint("MissingPermission")
    private fun scheduleAutonomousGroup() {
        autonomousGroupTask?.let(handler::removeCallbacks)
        val task = Runnable {
            if (!WifiDirectMeshPolicy.shouldCreateAutonomousGroup(
                    rescueActive = rescueActive,
                    connected = groupConnected,
                    discoveredPeers = discoveredDevices.size,
                )
            ) {
                return@Runnable
            }
            val actualManager = manager ?: return@Runnable
            val actualChannel = channel ?: return@Runnable
            actualManager.createGroup(actualChannel, action("create_group"))
        }
        autonomousGroupTask = task
        handler.postDelayed(task, WifiDirectMeshPolicy.AUTONOMOUS_GROUP_DELAY_MS)
    }

    @SuppressLint("MissingPermission")
    private fun requestConnectionInfo() {
        val actualManager = manager ?: return
        val actualChannel = channel ?: return
        actualManager.requestConnectionInfo(actualChannel) { info ->
            val ownerAddress = info.groupOwnerAddress?.hostAddress
            emit(
                available = true,
                groupOwner = info.isGroupOwner,
                groupOwnerAddress = ownerAddress,
            )
            if (info.groupFormed) {
                if (info.isGroupOwner) {
                    startEmergencyServer()
                } else if (ownerAddress != null) {
                    connectEmergencySocket(ownerAddress)
                }
            }
        }
    }

    fun sendEmergencyFrame(frame: ByteArray): Boolean {
        if (frame.isEmpty() ||
            frame.size > minOf(
                peerMaximumFrameSize,
                WifiDirectEmergencyFraming.MAXIMUM_FRAME_SIZE,
            )
        ) {
            return false
        }
        return synchronized(socketLock) {
            val output = emergencyOutput ?: return@synchronized false
            runCatching {
                output.writeInt(frame.size)
                output.write(frame)
                output.flush()
            }.onFailure {
                connected = false
                closeEmergencySocket()
                emit(available = true, reason = "emergency_send_failed")
            }.isSuccess
        }
    }

    private fun startEmergencyServer() {
        if (serverSocket != null || !active) return
        ioExecutor.execute {
            runCatching {
                ServerSocket().also { server ->
                    server.reuseAddress = true
                    server.bind(InetSocketAddress(WIFI_DIRECT_EMERGENCY_PORT))
                    serverSocket = server
                    while (active && !server.isClosed) {
                        val socket = server.accept()
                        runCatching { activateEmergencySocket(socket) }
                            .onFailure { runCatching { socket.close() } }
                    }
                }
            }.onFailure {
                if (active) {
                    emit(available = true, reason = "emergency_server_failed")
                }
            }
        }
    }

    private fun connectEmergencySocket(ownerAddress: String) {
        if (emergencySocket != null || !active) return
        ioExecutor.execute {
            runCatching {
                Socket().also { socket ->
                    socket.connect(
                        InetSocketAddress(ownerAddress, WIFI_DIRECT_EMERGENCY_PORT),
                        SOCKET_CONNECT_TIMEOUT_MS,
                    )
                    activateEmergencySocket(socket)
                }
            }.onFailure {
                if (active) {
                    emit(available = true, groupOwnerAddress = ownerAddress, reason = "emergency_connect_failed")
                }
            }
        }
    }

    private fun activateEmergencySocket(socket: Socket) {
        socket.tcpNoDelay = true
        val input = DataInputStream(socket.getInputStream())
        val output = DataOutputStream(socket.getOutputStream())
        output.write(WifiDirectEmergencyFraming.buildHello(gatewayId))
        output.flush()
        val peerHello = ByteArray(25)
        input.readFully(peerHello)
        val peerMaximum = WifiDirectEmergencyFraming.parseMaximumFrameSize(peerHello)
        synchronized(socketLock) {
            closeEmergencySocket()
            emergencySocket = socket
            emergencyOutput = output
            peerMaximumFrameSize = peerMaximum
            connected = true
        }
        emit(available = true)
        try {
            while (active && !socket.isClosed) {
                val length = input.readInt()
                require(length in 1..minOf(
                    peerMaximum,
                    WifiDirectEmergencyFraming.MAXIMUM_FRAME_SIZE,
                ))
                val frame = ByteArray(length)
                input.readFully(frame)
                if (allowEmergencyIngress()) {
                    onEmergencyFrame(frame)
                }
            }
        } finally {
            synchronized(socketLock) {
                if (emergencySocket === socket) {
                    closeEmergencySocket()
                    connected = false
                }
            }
            if (active) emit(available = true, reason = "emergency_disconnected")
        }
    }

    private fun allowEmergencyIngress(now: Long = System.currentTimeMillis()): Boolean =
        synchronized(ingressTimes) {
            val cutoff = now - INGRESS_WINDOW_MS
            while (!ingressTimes.isEmpty() && ingressTimes.first() < cutoff) {
                ingressTimes.removeFirst()
            }
            if (ingressTimes.size >= MAX_INGRESS_PER_WINDOW) {
                false
            } else {
                ingressTimes.addLast(now)
                true
            }
        }

    private fun closeSockets() {
        runCatching { serverSocket?.close() }
        serverSocket = null
        synchronized(socketLock) {
            closeEmergencySocket()
        }
        synchronized(ingressTimes) { ingressTimes.clear() }
    }

    private fun closeEmergencySocket() {
        runCatching { emergencySocket?.close() }
        emergencySocket = null
        emergencyOutput = null
        peerMaximumFrameSize = WifiDirectEmergencyFraming.MAXIMUM_FRAME_SIZE
    }

    private fun registerReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            appContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            appContext.registerReceiver(receiver, filter)
        }
        receiverRegistered = true
    }

    private fun hasPermission(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= 33) {
            Manifest.permission.NEARBY_WIFI_DEVICES
        } else {
            Manifest.permission.ACCESS_FINE_LOCATION
        }
        return ContextCompat.checkSelfPermission(
            appContext,
            permission,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun action(operation: String) = object : WifiP2pManager.ActionListener {
        override fun onSuccess() {
            emit(available = true)
        }

        override fun onFailure(reason: Int) {
            emit(available = true, reason = "$operation:$reason")
        }
    }

    private fun emit(
        available: Boolean,
        groupOwner: Boolean = false,
        groupOwnerAddress: String? = null,
        reason: String? = null,
    ) {
        onState(
            WifiDirectMeshState(
                available = available,
                active = active,
                connected = connected,
                groupOwner = groupOwner,
                groupOwnerAddress = groupOwnerAddress,
                reason = reason,
            ),
        )
    }

    private companion object {
        const val SERVICE_INSTANCE_PREFIX = "hearthbit-"
        const val SERVICE_TYPE = "_hearthbit._tcp"
        const val WIFI_DIRECT_EMERGENCY_PORT = 45_895
        const val SOCKET_CONNECT_TIMEOUT_MS = 5_000
        const val INGRESS_WINDOW_MS = 60_000L
        const val MAX_INGRESS_PER_WINDOW = 30
    }
}
