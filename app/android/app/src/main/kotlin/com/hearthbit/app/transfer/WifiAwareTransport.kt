package com.hearthbit.app.transfer

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.aware.AttachCallback
import android.net.wifi.aware.DiscoverySession
import android.net.wifi.aware.DiscoverySessionCallback
import android.net.wifi.aware.PeerHandle
import android.net.wifi.aware.PublishConfig
import android.net.wifi.aware.PublishDiscoverySession
import android.net.wifi.aware.SubscribeConfig
import android.net.wifi.aware.SubscribeDiscoverySession
import android.net.wifi.aware.WifiAwareManager
import android.net.wifi.aware.WifiAwareNetworkInfo
import android.net.wifi.aware.WifiAwareNetworkSpecifier
import android.net.wifi.aware.WifiAwareSession
import android.os.Handler
import android.os.HandlerThread
import androidx.annotation.RequiresApi
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.net.ServerSocket
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Transporte Wi-Fi Aware (NAN): datos directos entre teléfonos sin punto de
 * acceso ni Google Play Services.
 *
 * El emisor publica el servicio con el `transferId` (secreto, negociado por
 * BLE dentro de Noise) como identificador; el receptor se suscribe, pide el
 * data path cifrado con una passphrase derivada del mismo `transferId` y
 * descarga el contenedor por TCP. El contenido viaja además cifrado extremo a
 * extremo (contenedor HBT), así que la radio solo ve bytes opacos.
 *
 * Requiere API 29 (WifiAwareNetworkSpecifier con puerto). Cualquier fallo se
 * reporta a Flutter, que cae automáticamente a Nearby, LAN, BLE u óptico.
 */
@RequiresApi(29)
internal class WifiAwareTransport(
    private val context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val handlerThread = HandlerThread("hbt-aware").apply { start() }
    private val handler = Handler(handlerThread.looper)

    @Volatile
    private var transferId: String? = null

    @Volatile
    private var session: WifiAwareSession? = null

    @Volatile
    private var discovery: DiscoverySession? = null

    @Volatile
    private var serverSocket: ServerSocket? = null

    @Volatile
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    fun sendFile(transferId: String, filePath: String) {
        stop()
        this.transferId = transferId
        attach(transferId) { awareSession ->
            val server = ServerSocket(0)
            serverSocket = server
            acceptAndStream(transferId, server, filePath)
            val config = PublishConfig.Builder()
                .setServiceName(SERVICE_NAME)
                .setServiceSpecificInfo(transferId.toByteArray())
                .build()
            awareSession.publish(
                config,
                object : DiscoverySessionCallback() {
                    override fun onPublishStarted(session: PublishDiscoverySession) {
                        discovery = session
                    }

                    override fun onMessageReceived(peer: PeerHandle, message: ByteArray) {
                        val publishSession =
                            discovery as? PublishDiscoverySession ?: return
                        // El publicador también solicita la red para que el
                        // sistema establezca el data path hacia este puerto.
                        requestNetwork(
                            transferId,
                            WifiAwareNetworkSpecifier.Builder(publishSession, peer)
                                .setPskPassphrase(passphrase(transferId))
                                .setPort(server.localPort)
                                .build(),
                            onPeerInfo = null,
                        )
                    }

                    override fun onSessionConfigFailed() {
                        error(transferId, "Wi-Fi Aware rechazó la publicación")
                    }
                },
                handler,
            )
        }
    }

    fun receiveFile(transferId: String, destinationPath: String) {
        stop()
        this.transferId = transferId
        attach(transferId) { awareSession ->
            val config = SubscribeConfig.Builder()
                .setServiceName(SERVICE_NAME)
                .build()
            awareSession.subscribe(
                config,
                object : DiscoverySessionCallback() {
                    override fun onSubscribeStarted(session: SubscribeDiscoverySession) {
                        discovery = session
                    }

                    override fun onServiceDiscovered(
                        peer: PeerHandle,
                        serviceSpecificInfo: ByteArray?,
                        matchFilter: List<ByteArray>?,
                    ) {
                        if (serviceSpecificInfo?.decodeToString() != transferId) return
                        val subscribeSession =
                            discovery as? SubscribeDiscoverySession ?: return
                        subscribeSession.sendMessage(peer, 0, REQUEST)
                        requestNetwork(
                            transferId,
                            WifiAwareNetworkSpecifier.Builder(subscribeSession, peer)
                                .setPskPassphrase(passphrase(transferId))
                                .build(),
                        ) { network, info ->
                            download(transferId, network, info, destinationPath)
                        }
                    }

                    override fun onSessionConfigFailed() {
                        error(transferId, "Wi-Fi Aware rechazó la suscripción")
                    }
                },
                handler,
            )
        }
    }

    fun stop() {
        transferId = null
        networkCallback?.let { callback ->
            runCatching {
                context.getSystemService(ConnectivityManager::class.java)
                    ?.unregisterNetworkCallback(callback)
            }
        }
        networkCallback = null
        runCatching { serverSocket?.close() }
        serverSocket = null
        runCatching { discovery?.close() }
        discovery = null
        runCatching { session?.close() }
        session = null
    }

    private fun attach(transferId: String, onAttached: (WifiAwareSession) -> Unit) {
        val manager = context.getSystemService(WifiAwareManager::class.java)
        if (manager?.isAvailable != true) {
            error(transferId, "Wi-Fi Aware no está disponible en este momento")
            return
        }
        manager.attach(
            object : AttachCallback() {
                override fun onAttached(awareSession: WifiAwareSession) {
                    if (this@WifiAwareTransport.transferId != transferId) {
                        awareSession.close()
                        return
                    }
                    session = awareSession
                    onAttached(awareSession)
                }

                override fun onAttachFailed() {
                    error(transferId, "No se pudo iniciar la sesión Wi-Fi Aware")
                }
            },
            handler,
        )
    }

    private fun requestNetwork(
        transferId: String,
        specifier: WifiAwareNetworkSpecifier,
        onPeerInfo: ((Network, WifiAwareNetworkInfo) -> Unit)?,
    ) {
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI_AWARE)
            .setNetworkSpecifier(specifier)
            .build()
        val started = AtomicBoolean(false)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities,
            ) {
                val info = capabilities.transportInfo as? WifiAwareNetworkInfo ?: return
                if (onPeerInfo != null && started.compareAndSet(false, true)) {
                    onPeerInfo(network, info)
                }
            }

            override fun onUnavailable() {
                if (this@WifiAwareTransport.transferId == transferId) {
                    error(transferId, "El data path Wi-Fi Aware no se estableció")
                }
            }
        }
        networkCallback = callback
        context.getSystemService(ConnectivityManager::class.java)
            ?.requestNetwork(request, callback)
    }

    private fun acceptAndStream(
        transferId: String,
        server: ServerSocket,
        filePath: String,
    ) {
        thread(name = "hbt-aware-send") {
            runCatching {
                server.accept().use { socket ->
                    val file = File(filePath)
                    DataOutputStream(socket.getOutputStream().buffered()).use { output ->
                        output.writeLong(file.length())
                        file.inputStream().use { input ->
                            val buffer = ByteArray(BUFFER_SIZE)
                            var sent = 0L
                            while (true) {
                                val read = input.read(buffer)
                                if (read < 0) break
                                output.write(buffer, 0, read)
                                sent += read
                                progress(transferId, sent)
                            }
                        }
                        output.flush()
                    }
                }
                emit(mapOf("type" to "wifiAwareDone", "transferId" to transferId))
            }.onFailure {
                if (this.transferId == transferId) {
                    error(transferId, "Envío Wi-Fi Aware interrumpido: ${it.message}")
                }
            }
        }
    }

    private fun download(
        transferId: String,
        network: Network,
        info: WifiAwareNetworkInfo,
        destinationPath: String,
    ) {
        thread(name = "hbt-aware-receive") {
            runCatching {
                network.socketFactory
                    .createSocket(info.peerIpv6Addr, info.port)
                    .use { socket ->
                        DataInputStream(socket.getInputStream().buffered()).use { input ->
                            val total = input.readLong()
                            require(total >= 0) { "Cabecera de tamaño inválida" }
                            File(destinationPath).outputStream().use { output ->
                                val buffer = ByteArray(BUFFER_SIZE)
                                var received = 0L
                                while (received < total) {
                                    val target =
                                        minOf(buffer.size.toLong(), total - received)
                                    val read = input.read(buffer, 0, target.toInt())
                                    check(read >= 0) { "Conexión cerrada antes de tiempo" }
                                    output.write(buffer, 0, read)
                                    received += read
                                    progress(transferId, received)
                                }
                            }
                        }
                    }
                emit(mapOf("type" to "wifiAwareDone", "transferId" to transferId))
            }.onFailure {
                if (this.transferId == transferId) {
                    error(transferId, "Descarga Wi-Fi Aware interrumpida: ${it.message}")
                }
            }
        }
    }

    private fun progress(transferId: String, bytes: Long) {
        emit(
            mapOf(
                "type" to "wifiAwareProgress",
                "transferId" to transferId,
                "bytes" to bytes,
            ),
        )
    }

    private fun error(transferId: String, message: String) {
        emit(
            mapOf(
                "type" to "wifiAwareError",
                "transferId" to transferId,
                "message" to message,
            ),
        )
    }

    /** La passphrase WPA3 del data path se deriva del transferId secreto. */
    private fun passphrase(transferId: String): String = "hbt-$transferId"

    private companion object {
        const val SERVICE_NAME = "hearthbit-hbt"
        const val BUFFER_SIZE = 64 * 1024
        val REQUEST = "REQ".toByteArray()
    }
}
