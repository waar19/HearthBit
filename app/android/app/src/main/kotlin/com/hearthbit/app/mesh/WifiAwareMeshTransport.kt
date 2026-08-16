package com.hearthbit.app.mesh

import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.aware.AttachCallback
import android.net.wifi.aware.DiscoverySession
import android.net.wifi.aware.DiscoverySessionCallback
import android.net.wifi.aware.PeerHandle
import android.net.wifi.aware.PublishConfig
import android.net.wifi.aware.PublishDiscoverySession
import android.net.wifi.aware.SubscribeConfig
import android.net.wifi.aware.SubscribeDiscoverySession
import android.net.wifi.aware.WifiAwareManager
import android.net.wifi.aware.WifiAwareSession
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import androidx.annotation.RequiresApi
import java.util.ArrayDeque

internal object WifiAwareMeshPolicy {
    const val MAXIMUM_FOLLOW_UP_BYTES = 255
    const val MAXIMUM_PENDING_FRAMES = 16

    fun shouldRun(rescueActive: Boolean, supported: Boolean): Boolean =
        rescueActive && supported

    fun acceptsFrame(frame: ByteArray): Boolean =
        frame.isNotEmpty() && frame.size <= MAXIMUM_FOLLOW_UP_BYTES
}

internal data class WifiAwareMeshState(
    val available: Boolean,
    val active: Boolean,
    val peers: Int,
    val reason: String? = null,
)

internal interface WifiAwareMeshLink {
    fun start()
    fun stop()
    fun send(frame: ByteArray): Boolean
}

internal object WifiAwareMeshLinkFactory {
    fun create(
        context: Context,
        onFrame: (ByteArray) -> Unit,
        onState: (WifiAwareMeshState) -> Unit,
    ): WifiAwareMeshLink? =
        if (Build.VERSION.SDK_INT >= 26 &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_AWARE)
        ) {
            WifiAwareMeshTransport(context, onFrame, onState)
        } else {
            null
        }
}

/**
 * Portadora de frames SOS cortos mediante mensajes follow-up de Wi-Fi Aware.
 * No abre un data path: el servicio dedicado limita la carga a 255 bytes y el
 * motor aplica después la validación Ed25519 y el dedupe normales.
 */
@RequiresApi(26)
private class WifiAwareMeshTransport(
    context: Context,
    private val onFrame: (ByteArray) -> Unit,
    private val onState: (WifiAwareMeshState) -> Unit,
) : WifiAwareMeshLink {
    private val appContext = context.applicationContext
    private val manager = appContext.getSystemService(WifiAwareManager::class.java)
    private val handlerThread = HandlerThread("mesh-aware").apply { start() }
    private val handler = Handler(handlerThread.looper)
    private val publishPeers = mutableSetOf<PeerHandle>()
    private val subscribePeers = mutableSetOf<PeerHandle>()
    private val pending = ArrayDeque<ByteArray>()
    private var awareSession: WifiAwareSession? = null
    private var publishSession: PublishDiscoverySession? = null
    private var subscribeSession: SubscribeDiscoverySession? = null
    @Volatile
    private var active = false
    private var messageId = 1

    override fun start() {
        handler.post {
            if (active) return@post
            if (manager?.isAvailable != true) {
                emit(available = false, reason = "wifi_aware_unavailable")
                return@post
            }
            active = true
            emit(available = true)
            manager.attach(
                object : AttachCallback() {
                    override fun onAttached(session: WifiAwareSession) {
                        if (!active) {
                            session.close()
                            return
                        }
                        awareSession = session
                        publish(session)
                        subscribe(session)
                    }

                    override fun onAttachFailed() {
                        active = false
                        emit(available = true, reason = "wifi_aware_attach_failed")
                    }
                },
                handler,
            )
        }
    }

    override fun stop() {
        handler.post {
            active = false
            publishPeers.clear()
            subscribePeers.clear()
            pending.clear()
            runCatching { publishSession?.close() }
            runCatching { subscribeSession?.close() }
            runCatching { awareSession?.close() }
            publishSession = null
            subscribeSession = null
            awareSession = null
            emit(available = manager?.isAvailable == true)
        }
    }

    override fun send(frame: ByteArray): Boolean {
        if (!WifiAwareMeshPolicy.acceptsFrame(frame)) return false
        val copy = frame.copyOf()
        handler.post {
            if (!active) return@post
            if (publishPeers.isEmpty() && subscribePeers.isEmpty()) {
                if (pending.size >= WifiAwareMeshPolicy.MAXIMUM_PENDING_FRAMES) {
                    pending.removeFirst()
                }
                pending.addLast(copy)
            } else {
                sendToPeers(copy)
            }
        }
        return active
    }

    private fun publish(session: WifiAwareSession) {
        session.publish(
            PublishConfig.Builder()
                .setServiceName(SERVICE_NAME)
                .setServiceSpecificInfo(PROTOCOL_VERSION)
                .build(),
            callback(
                onStarted = { discovery ->
                    publishSession = discovery as PublishDiscoverySession
                },
                publisher = true,
            ),
            handler,
        )
    }

    private fun subscribe(session: WifiAwareSession) {
        session.subscribe(
            SubscribeConfig.Builder()
                .setServiceName(SERVICE_NAME)
                .build(),
            callback(
                onStarted = { discovery ->
                    subscribeSession = discovery as SubscribeDiscoverySession
                },
                publisher = false,
            ),
            handler,
        )
    }

    private fun callback(
        onStarted: (DiscoverySession) -> Unit,
        publisher: Boolean,
    ) =
        object : DiscoverySessionCallback() {
            override fun onPublishStarted(session: PublishDiscoverySession) {
                onStarted(session)
            }

            override fun onSubscribeStarted(session: SubscribeDiscoverySession) {
                onStarted(session)
            }

            override fun onServiceDiscovered(
                peer: PeerHandle,
                serviceSpecificInfo: ByteArray?,
                matchFilter: List<ByteArray>?,
            ) {
                if (serviceSpecificInfo?.contentEquals(PROTOCOL_VERSION) != true) return
                addPeer(peer, publisher)
            }

            override fun onMessageReceived(peer: PeerHandle, message: ByteArray) {
                if (!WifiAwareMeshPolicy.acceptsFrame(message)) return
                addPeer(peer, publisher)
                onFrame(message.copyOf())
            }

            override fun onSessionConfigFailed() {
                emit(available = true, reason = "wifi_aware_discovery_failed")
            }
        }

    private fun addPeer(peer: PeerHandle, publisher: Boolean) {
        val target = if (publisher) publishPeers else subscribePeers
        if (target.add(peer)) {
            emit(available = true)
            while (pending.isNotEmpty()) {
                sendToPeers(pending.removeFirst())
            }
        }
    }

    private fun sendToPeers(frame: ByteArray) {
        val currentId = messageId++
        publishSession?.let { session ->
            publishPeers.forEach { peer -> session.sendMessage(peer, currentId, frame) }
        }
        subscribeSession?.let { session ->
            subscribePeers.forEach { peer -> session.sendMessage(peer, currentId, frame) }
        }
    }

    private fun emit(available: Boolean, reason: String? = null) {
        onState(
            WifiAwareMeshState(
                available = available,
                active = active,
                peers = publishPeers.size + subscribePeers.size,
                reason = reason,
            ),
        )
    }

    private companion object {
        const val SERVICE_NAME = "hearthbit-mesh"
        val PROTOCOL_VERSION = byteArrayOf(1)
    }
}
