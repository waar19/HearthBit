package com.hearthbit.app.transfer

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
import java.io.File
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.concurrent.Executors

internal object WifiDirectTransferPolicy {
    const val PORT = 45_896
    const val MAXIMUM_CONTAINER_BYTES = 600L * 1024 * 1024

    fun isValidContainerSize(bytes: Long): Boolean = bytes in 1..MAXIMUM_CONTAINER_BYTES
}

internal object WifiDirectTransferSecrets {
    private const val DOMAIN = "hearthbit-wifi-direct-discovery-v1:"

    fun rendezvousToken(transferId: String): String {
        require(transferId.isNotBlank()) { "transferId must not be blank" }
        return MessageDigest.getInstance("SHA-256")
            .digest("$DOMAIN$transferId".toByteArray(StandardCharsets.UTF_8))
            .take(12)
            .joinToString(separator = "") { "%02x".format(it) }
    }
}

/**
 * Mueve el contenedor HBT cifrado por un grupo Wi-Fi Direct.
 *
 * El receptor descubre un servicio cuyo nombre contiene un token derivado del
 * transferId negociado por Noise. Tras formar el grupo, ambos extremos
 * autentican el socket con ese token antes de transmitir el blob opaco.
 */
internal class WifiDirectTransport(
    context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val appContext = context.applicationContext
    private val manager =
        appContext.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
    private var channel = manager?.initialize(appContext, Looper.getMainLooper(), null)
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newCachedThreadPool()
    private var receiverRegistered = false
    private var localService: WifiP2pDnsSdServiceInfo? = null
    private var serviceRequest: WifiP2pDnsSdServiceRequest? = null
    private var initiatedConnection = false

    @Volatile private var transferId: String? = null
    @Volatile private var sending = false
    @Volatile private var sourcePath: String? = null
    @Volatile private var destinationPath: String? = null
    @Volatile private var serverSocket: ServerSocket? = null
    @Volatile private var dataSocket: Socket? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    @Suppress("DEPRECATION")
                    val networkInfo =
                        intent.getParcelableExtra<NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
                    if (networkInfo?.isConnected == true) {
                        requestConnectionInfo()
                    } else {
                        closeSockets()
                    }
                }
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val enabled = intent.getIntExtra(
                        WifiP2pManager.EXTRA_WIFI_STATE,
                        WifiP2pManager.WIFI_P2P_STATE_DISABLED,
                    ) == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                    if (!enabled) currentId()?.let { error(it, "Wi-Fi Direct no está disponible") }
                }
            }
        }
    }

    fun isSupported(): Boolean =
        manager != null &&
            appContext.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)

    fun sendFile(transferId: String, filePath: String) {
        val file = File(filePath)
        require(file.isFile && WifiDirectTransferPolicy.isValidContainerSize(file.length())) {
            "Invalid HBT container"
        }
        start(transferId, isSender = true, path = filePath)
    }

    fun receiveFile(transferId: String, destinationPath: String) {
        start(transferId, isSender = false, path = destinationPath)
    }

    @SuppressLint("MissingPermission")
    private fun start(transferId: String, isSender: Boolean, path: String) {
        stop()
        require(isSupported() && hasPermission()) { "Wi-Fi Direct unavailable or denied" }
        this.transferId = transferId
        sending = isSender
        sourcePath = path.takeIf { isSender }
        destinationPath = path.takeUnless { isSender }
        registerReceiver()
        val actualManager = requireNotNull(manager)
        val actualChannel = channel ?: actualManager.initialize(
            appContext,
            Looper.getMainLooper(),
            null,
        ).also { channel = it }
        val token = WifiDirectTransferSecrets.rendezvousToken(transferId)
        if (isSender) {
            localService = WifiP2pDnsSdServiceInfo.newInstance(
                "$INSTANCE_PREFIX$token",
                SERVICE_TYPE,
                mapOf("v" to "1", "token" to token, "port" to WifiDirectTransferPolicy.PORT.toString()),
            ).also { service ->
                actualManager.addLocalService(
                    actualChannel,
                    service,
                    action(transferId, "No se pudo anunciar Wi-Fi Direct"),
                )
            }
        } else {
            actualManager.setDnsSdResponseListeners(
                actualChannel,
                { instanceName, registrationType, device ->
                    if (registrationType.startsWith(SERVICE_TYPE) &&
                        instanceName == "$INSTANCE_PREFIX$token"
                    ) {
                        connect(transferId, device)
                    }
                },
                { _, _, _ -> },
            )
            serviceRequest = WifiP2pDnsSdServiceRequest.newInstance().also { request ->
                actualManager.addServiceRequest(
                    actualChannel,
                    request,
                    action(transferId, "No se pudo preparar la búsqueda Wi-Fi Direct"),
                )
            }
            actualManager.discoverServices(
                actualChannel,
                action(transferId, "No se pudo buscar por Wi-Fi Direct"),
            )
        }
    }

    @SuppressLint("MissingPermission")
    fun stop() {
        val actualManager = manager
        val actualChannel = channel
        if (actualManager != null && actualChannel != null) {
            serviceRequest?.let { actualManager.removeServiceRequest(actualChannel, it, null) }
            localService?.let { actualManager.removeLocalService(actualChannel, it, null) }
            actualManager.cancelConnect(actualChannel, null)
            if (initiatedConnection) actualManager.removeGroup(actualChannel, null)
        }
        initiatedConnection = false
        serviceRequest = null
        localService = null
        closeSockets()
        transferId = null
        sourcePath = null
        destinationPath = null
        if (receiverRegistered) {
            runCatching { appContext.unregisterReceiver(receiver) }
            receiverRegistered = false
        }
    }

    @SuppressLint("MissingPermission")
    private fun connect(transferId: String, device: WifiP2pDevice) {
        if (currentId() != transferId || initiatedConnection) return
        val actualManager = manager ?: return
        val actualChannel = channel ?: return
        @Suppress("DEPRECATION")
        val config = WifiP2pConfig().apply {
            deviceAddress = device.deviceAddress
            groupOwnerIntent = 0
        }
        initiatedConnection = true
        actualManager.connect(
            actualChannel,
            config,
            action(transferId, "No se pudo formar el enlace Wi-Fi Direct"),
        )
    }

    @SuppressLint("MissingPermission")
    private fun requestConnectionInfo() {
        val id = currentId() ?: return
        val actualManager = manager ?: return
        val actualChannel = channel ?: return
        actualManager.requestConnectionInfo(actualChannel) { info ->
            if (!info.groupFormed || currentId() != id) return@requestConnectionInfo
            val ownerAddress = info.groupOwnerAddress?.hostAddress ?: return@requestConnectionInfo
            if (info.isGroupOwner) {
                startServer(id)
            } else {
                handler.postDelayed({ connectSocket(id, ownerAddress) }, CLIENT_CONNECT_DELAY_MS)
            }
        }
    }

    private fun startServer(transferId: String) {
        if (serverSocket != null) return
        executor.execute {
            runCatching {
                ServerSocket().also { server ->
                    server.reuseAddress = true
                    server.bind(InetSocketAddress(WifiDirectTransferPolicy.PORT))
                    serverSocket = server
                    openSession(transferId, server.accept())
                }
            }.onFailure {
                if (currentId() == transferId) error(transferId, "Falló Wi-Fi Direct: ${it.message}")
            }
        }
    }

    private fun connectSocket(transferId: String, address: String) {
        if (dataSocket != null || currentId() != transferId) return
        executor.execute {
            runCatching {
                Socket().also { socket ->
                    socket.connect(
                        InetSocketAddress(address, WifiDirectTransferPolicy.PORT),
                        SOCKET_CONNECT_TIMEOUT_MS,
                    )
                    openSession(transferId, socket)
                }
            }.onFailure {
                if (currentId() == transferId) error(transferId, "Falló Wi-Fi Direct: ${it.message}")
            }
        }
    }

    private fun openSession(transferId: String, socket: Socket) {
        dataSocket = socket
        socket.tcpNoDelay = true
        val input = DataInputStream(socket.getInputStream().buffered())
        val output = DataOutputStream(socket.getOutputStream().buffered())
        val token = WifiDirectTransferSecrets.rendezvousToken(transferId)
        output.writeInt(HELLO_MAGIC)
        output.writeByte(PROTOCOL_VERSION)
        output.writeBoolean(sending)
        output.writeUTF(token)
        output.flush()
        require(input.readInt() == HELLO_MAGIC && input.readUnsignedByte() == PROTOCOL_VERSION)
        val peerSending = input.readBoolean()
        require(input.readUTF() == token && peerSending != sending) { "Invalid peer handshake" }
        if (sending) {
            streamFile(transferId, output)
        } else {
            receiveFile(transferId, input)
        }
        emit(mapOf("type" to "wifiDirectDone", "transferId" to transferId))
    }

    private fun streamFile(transferId: String, output: DataOutputStream) {
        val file = File(requireNotNull(sourcePath))
        output.writeLong(file.length())
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(BUFFER_SIZE)
            var sent = 0L
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                output.write(buffer, 0, read)
                sent += read
                progress(transferId, sent, file.length())
            }
        }
        output.flush()
    }

    private fun receiveFile(transferId: String, input: DataInputStream) {
        val total = input.readLong()
        require(WifiDirectTransferPolicy.isValidContainerSize(total)) { "Invalid size header" }
        File(requireNotNull(destinationPath)).outputStream().buffered().use { output ->
            val buffer = ByteArray(BUFFER_SIZE)
            var received = 0L
            while (received < total) {
                val read = input.read(buffer, 0, minOf(buffer.size.toLong(), total - received).toInt())
                check(read >= 0) { "Connection closed prematurely" }
                output.write(buffer, 0, read)
                received += read
                progress(transferId, received, total)
            }
        }
    }

    private fun progress(transferId: String, bytes: Long, total: Long) {
        emit(
            mapOf(
                "type" to "wifiDirectProgress",
                "transferId" to transferId,
                "bytes" to bytes,
                "total" to total,
            ),
        )
    }

    private fun error(transferId: String, message: String) {
        emit(mapOf("type" to "wifiDirectError", "transferId" to transferId, "message" to message))
    }

    private fun currentId(): String? = transferId

    private fun closeSockets() {
        runCatching { dataSocket?.close() }
        dataSocket = null
        runCatching { serverSocket?.close() }
        serverSocket = null
    }

    private fun registerReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
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
        return ContextCompat.checkSelfPermission(appContext, permission) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun action(transferId: String, message: String) =
        object : WifiP2pManager.ActionListener {
            override fun onSuccess() = Unit

            override fun onFailure(reason: Int) {
                if (currentId() == transferId) error(transferId, "$message ($reason)")
            }
        }

    private companion object {
        const val INSTANCE_PREFIX = "hearthbit-hbt-"
        const val SERVICE_TYPE = "_hearthbit-hbt._tcp"
        const val HELLO_MAGIC = 0x48425444
        const val PROTOCOL_VERSION = 1
        const val BUFFER_SIZE = 64 * 1024
        const val CLIENT_CONNECT_DELAY_MS = 500L
        const val SOCKET_CONNECT_TIMEOUT_MS = 8_000
    }
}
