package com.hearthbit.app.mesh

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanRecord
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import com.hearthbit.app.R
import java.io.ByteArrayOutputStream
import java.util.Collections
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

internal class MeshEngine(
    private val context: Context,
    requiredRole: MeshNodeRole? = null,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val bluetoothManager = context.getSystemService(BluetoothManager::class.java)
    private val adapter get() = bluetoothManager.adapter
    private val identity = MeshIdentity(context).also { identity ->
        val startupRole = MeshStartupRolePolicy.resolve(identity.nodeRole, requiredRole)
        if (identity.nodeRole != startupRole) {
            identity.nodeRole = startupRole
        }
    }
    private val noiseSessions = NoiseSessionManagerLite(identity.peerIdHex, identity.noisePrivateKey)
    private val seen = Collections.synchronizedMap(
        object : LinkedHashMap<String, Long>(512, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Long>?): Boolean =
                size > 2_000
        },
    )
    private val peers = ConcurrentHashMap<String, Peer>()
    private val pendingPrivate = ConcurrentHashMap<String, MutableList<PendingPrivate>>()
    private val pendingFrames = ConcurrentHashMap<String, MutableList<ByteArray>>()
    private val pendingCourier =
        ConcurrentHashMap<String, MutableList<MeshProtocol.Packet>>()
    private val clientGatts = ConcurrentHashMap<String, BluetoothGatt>()
    private val clientCharacteristics =
        ConcurrentHashMap<String, BluetoothGattCharacteristic>()
    private val clientMaximumGattValueSizes = ConcurrentHashMap<String, Int>()
    private val clientWriteLock = Any()
    private val clientWriteQueues = mutableMapOf<String, ArrayDeque<ByteArray>>()
    private val clientWritesInFlight = mutableSetOf<String>()
    private val clientReady = ConcurrentHashMap.newKeySet<String>()
    private val serverSubscribers = ConcurrentHashMap.newKeySet<BluetoothDevice>()
    private val serverMaximumGattValueSizes = ConcurrentHashMap<String, Int>()
    private val serverNotificationLock = Any()
    private val serverNotificationQueues = mutableMapOf<String, ArrayDeque<ByteArray>>()
    private val serverNotificationsInFlight = mutableSetOf<String>()
    private val storeForward = StoreForwardCache(context)
    private val fragmentReassembler = MeshFragmentReassembler()
    private val packetFragmenter = MeshPacketFragmenter()
    private val lastSyncRequestByAddress = ConcurrentHashMap<String, Long>()
    private val syncResponseTimes = ConcurrentHashMap<String, ArrayDeque<Long>>()
    private val syncPackets = Collections.synchronizedMap(
        object : LinkedHashMap<String, MeshProtocol.Packet>(SYNC_STORE_CAPACITY, 0.75f, true) {
            override fun removeEldestEntry(
                eldest: MutableMap.MutableEntry<String, MeshProtocol.Packet>?,
            ): Boolean = size > SYNC_STORE_CAPACITY
        },
    )
    private val remoteRadarConsents = ConcurrentHashMap<String, RemoteRadarConsent>()
    private val tentativeRadarReads = ConcurrentHashMap<String, String>()
    private val genericPresenceTracker = GenericBlePresenceTracker()

    /**
     * Dirección MAC -> peerId de vecinos directos. Se alimenta con el peerId
     * del scan response (Android) y con anuncios recibidos con TTL intacto
     * (un salto), que solo pueden venir del propio emisor.
     */
    private val addressToPeer = ConcurrentHashMap<String, String>()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var gattServer: BluetoothGattServer? = null
    private var serverCharacteristic: BluetoothGattCharacteristic? = null

    @Volatile
    private var running = false

    @Volatile
    private var advertising = false

    @Volatile
    private var currentStatus = "stopped"

    @Volatile
    private var localRole = identity.nodeRole

    private var advertiseCallback: AdvertiseCallback? = null
    private var advertiseAttempt = 0
    private var advertiseGeneration = 0
    private var advertiseWatchdog: Runnable? = null
    private var genericPresenceEmitRunnable: Runnable? = null

    /** Peer objetivo del radar de rescate; null cuando el radar está apagado. */
    @Volatile
    private var radarPeerId: String? = null

    data class Peer(
        val id: String,
        val nickname: String,
        val signingPublicKey: ByteArray,
        val noisePublicKey: ByteArray,
        var supportsTransfers: Boolean,
        var role: MeshNodeRole = MeshNodeRole.PHONE_RELAY,
        var lastSeen: Long = System.currentTimeMillis(),
    )

    private data class PendingPrivate(val id: String, val content: String)
    private data class RemoteRadarConsent(val expiresAt: Long, val source: String)

    val peerId: String get() = identity.peerIdHex
    val nickname: String get() = identity.nickname

    fun stateSnapshot(): Map<String, Any?> = mapOf(
        "type" to "snapshot",
        "status" to currentStatus,
        "peerId" to peerId,
        "nickname" to nickname,
        "role" to localRole.wireName,
        "radarConsentUntil" to activeLocalRadarConsentUntil(),
        "peers" to peersSnapshot(),
        "presences" to genericPresenceTracker.snapshot(System.currentTimeMillis())
            .map(GenericBlePresenceTracker.Presence::toEventMap),
    )

    @SuppressLint("MissingPermission")
    fun start() {
        check(adapter != null && adapter.isEnabled) {
            context.getString(R.string.error_bluetooth_off)
        }
        // Reinicio real: si ya estaba corriendo (por ejemplo tras un fallo de
        // advertising) se liberan los recursos antes de volver a intentarlo.
        if (running) stopInternal(notify = false)
        running = true
        emitStatus("starting")
        if (localRole != MeshNodeRole.PHONE_BEACON) {
            startGattServer()
            startScanning()
            startGenericBeaconScanning()
        }
        startAdvertising()
    }

    fun ensureStarted() {
        if (running) {
            if (advertising || currentStatus == "starting") {
                emit(stateSnapshot())
            } else {
                advertiseAttempt = 0
                emitStatus("starting")
                startAdvertising()
            }
            return
        }
        start()
    }

    fun configureStartupRole(requiredRole: MeshNodeRole) {
        check(!running || localRole == requiredRole) {
            "No se puede cambiar el rol después de iniciar BLE"
        }
        if (localRole != requiredRole) {
            localRole = requiredRole
            identity.nodeRole = requiredRole
        }
    }

    fun stop() {
        if (!running) return
        stopInternal(notify = true)
    }

    @SuppressLint("MissingPermission")
    private fun stopInternal(notify: Boolean) {
        running = false
        advertising = false
        advertiseGeneration += 1
        advertiseWatchdog?.let(mainHandler::removeCallbacks)
        advertiseWatchdog = null
        advertiseCallback?.let { callback ->
            runCatching { adapter.bluetoothLeAdvertiser?.stopAdvertising(callback) }
        }
        advertiseCallback = null
        advertiseAttempt = 0
        stopRadar()
        addressToPeer.clear()
        runCatching { adapter.bluetoothLeScanner?.stopScan(scanCallback) }
        runCatching { adapter.bluetoothLeScanner?.stopScan(genericBeaconScanCallback) }
        genericPresenceEmitRunnable?.let(mainHandler::removeCallbacks)
        genericPresenceEmitRunnable = null
        genericPresenceTracker.clear()
        clientGatts.values.forEach { runCatching { it.close() } }
        clientGatts.clear()
        clientCharacteristics.clear()
        clientMaximumGattValueSizes.clear()
        clientReady.clear()
        synchronized(clientWriteLock) {
            clientWriteQueues.clear()
            clientWritesInFlight.clear()
        }
        serverSubscribers.clear()
        serverMaximumGattValueSizes.clear()
        synchronized(serverNotificationLock) {
            serverNotificationQueues.clear()
            serverNotificationsInFlight.clear()
        }
        runCatching { gattServer?.close() }
        gattServer = null
        serverCharacteristic = null
        noiseSessions.close()
        fragmentReassembler.clear()
        lastSyncRequestByAddress.clear()
        syncResponseTimes.clear()
        pendingCourier.clear()
        remoteRadarConsents.clear()
        tentativeRadarReads.clear()
        if (notify) emitStatus("stopped")
    }

    fun updateNickname(value: String) {
        identity.nickname = value.trim().ifEmpty { "SOS-${peerId.takeLast(4)}" }
        sendAnnouncement()
    }

    fun updateRole(value: String) {
        val nextRole = requireNotNull(MeshNodeRole.fromWireName(value)) {
            "Rol de nodo no válido"
        }
        if (nextRole == localRole) return
        val previousRole = localRole
        localRole = nextRole
        identity.nodeRole = localRole
        sendNodeCapability()
        if (running) {
            if (localRole == MeshNodeRole.PHONE_BEACON) {
                mainHandler.postDelayed({ enterPresenceOnlyMode() }, ROLE_TRANSITION_DELAY_MS)
            } else if (previousRole == MeshNodeRole.PHONE_BEACON) {
                enterDataRelayMode()
            } else {
                restartAdvertising()
            }
        }
        emit(stateSnapshot())
    }

    @SuppressLint("MissingPermission")
    private fun enterPresenceOnlyMode() {
        if (!running || localRole != MeshNodeRole.PHONE_BEACON) return
        runCatching { adapter.bluetoothLeScanner?.stopScan(scanCallback) }
        runCatching { adapter.bluetoothLeScanner?.stopScan(genericBeaconScanCallback) }
        genericPresenceEmitRunnable?.let(mainHandler::removeCallbacks)
        genericPresenceEmitRunnable = null
        genericPresenceTracker.clear()
        clientGatts.values.forEach { runCatching { it.close() } }
        clientGatts.clear()
        clientCharacteristics.clear()
        clientMaximumGattValueSizes.clear()
        clientReady.clear()
        synchronized(clientWriteLock) {
            clientWriteQueues.clear()
            clientWritesInFlight.clear()
        }
        serverSubscribers.clear()
        serverMaximumGattValueSizes.clear()
        synchronized(serverNotificationLock) {
            serverNotificationQueues.clear()
            serverNotificationsInFlight.clear()
        }
        runCatching { gattServer?.close() }
        gattServer = null
        serverCharacteristic = null
        noiseSessions.close()
        restartAdvertising()
    }

    private fun enterDataRelayMode() {
        if (!running || localRole == MeshNodeRole.PHONE_BEACON) return
        if (gattServer == null) startGattServer()
        startScanning()
        startGenericBeaconScanning()
        restartAdvertising()
        mainHandler.postDelayed({ sendAnnouncement() }, ROLE_TRANSITION_DELAY_MS)
    }

    @SuppressLint("MissingPermission")
    private fun restartAdvertising() {
        advertising = false
        advertiseGeneration += 1
        cancelAdvertiseWatchdog()
        advertiseCallback?.let { callback ->
            runCatching { adapter.bluetoothLeAdvertiser?.stopAdvertising(callback) }
        }
        advertiseCallback = null
        advertiseAttempt = 0
        startAdvertising()
    }

    fun sendPublic(content: String, channel: String? = null): String {
        check(localRole.canOriginateChat) {
            "El rol ${localRole.wireName} no puede originar chat"
        }
        check(content.isNotBlank())
        val id = UUID.randomUUID().toString().uppercase()
        val payload = MeshProtocol.encodeInteropPublicMessage(content.take(2_000))
        val packet = identity.sign(
            MeshProtocol.Packet(
                type = MeshProtocol.TYPE_MESSAGE,
                ttl = MeshProtocol.TTL,
                timestamp = System.currentTimeMillis(),
                senderId = identity.peerId,
                payload = payload,
            ),
        )
        broadcast(packet)
        emitMessage(id, nickname, content, peerId, false, true, packet.timestamp, channel)
        return id
    }

    fun sendSos(content: String, latitude: Double?, longitude: Double?): String {
        val location = if (latitude != null && longitude != null) {
            "|$latitude|$longitude"
        } else {
            "||"
        }
        return sendPublic("SOS|$content$location", "sos")
    }

    fun setRadarConsent(enabled: Boolean, durationMs: Long = RadarConsentProtocol.MANUAL_DURATION_MS) {
        val now = System.currentTimeMillis()
        if (enabled) {
            val boundedDuration = durationMs.coerceIn(1L, RadarConsentProtocol.MAX_GRANT_DURATION_MS)
            identity.radarConsentUntil = now + boundedDuration
            broadcastRadarConsent(grant = true)
        } else {
            identity.radarConsentUntil = 0
            broadcastRadarConsent(grant = false)
        }
        emitRadarConsent()
    }

    fun sendPrivate(peerIdHex: String, content: String): String {
        check(localRole.canOriginateChat) {
            "El rol ${localRole.wireName} no puede originar chat"
        }
        val peer = peers[peerIdHex]
        require(peer != null) {
            context.getString(R.string.error_peer_unavailable)
        }
        require(peer.role.canOriginateChat) {
            "El rol ${peer.role.wireName} no admite chat"
        }
        val id = UUID.randomUUID().toString().uppercase()
        if (noiseSessions.isEstablished(peerIdHex)) {
            sendEncryptedPrivate(peerIdHex, id, content)
        } else {
            pendingPrivate.computeIfAbsent(peerIdHex) { Collections.synchronizedList(mutableListOf()) }
                .add(PendingPrivate(id, content))
            initiateHandshake(peerIdHex)
        }
        emitMessage(
            id,
            nickname,
            content,
            peerIdHex,
            true,
            true,
            System.currentTimeMillis(),
            null,
        )
        return id
    }

    /**
     * Envía una trama HBT al peer por la sesión Noise. Si aún no hay sesión,
     * la trama queda en cola y se dispara el handshake.
     */
    fun sendTransferFrame(peerIdHex: String, frame: ByteArray) {
        require(peers.containsKey(peerIdHex)) {
            context.getString(R.string.error_peer_unavailable)
        }
        require(frame.size <= MAX_TRANSFER_FRAME) {
            context.getString(R.string.error_frame_too_large)
        }
        if (noiseSessions.isEstablished(peerIdHex)) {
            sendEncryptedFrame(peerIdHex, frame)
        } else {
            pendingFrames.computeIfAbsent(peerIdHex) {
                Collections.synchronizedList(mutableListOf())
            }.add(frame)
            initiateHandshake(peerIdHex)
        }
    }

    fun signPayload(data: ByteArray): ByteArray = identity.signBytes(data)

    fun verifyPeerSignature(peerIdHex: String, data: ByteArray, signature: ByteArray): Boolean {
        val peer = peers[peerIdHex] ?: return false
        return identity.verifyBytes(data, signature, peer.signingPublicKey)
    }

    private fun sendEncryptedFrame(peerIdHex: String, frame: ByteArray) {
        val typedPayload = byteArrayOf(MeshProtocol.NOISE_TRANSFER_FRAME) + frame
        val encrypted = runCatching { noiseSessions.encrypt(peerIdHex, typedPayload) }.getOrElse {
            emitError(context.getString(R.string.error_frame_encrypt))
            return
        }
        sendNoisePacket(
            MeshProtocol.TYPE_NOISE_ENCRYPTED,
            peerIdHex.hexToBytes(),
            encrypted,
        )
    }

    fun peersSnapshot(): List<Map<String, Any?>> {
        val now = System.currentTimeMillis()
        pruneRadarConsents(now)
        return peers.values.sortedByDescending(Peer::lastSeen).map {
            val consent = remoteRadarConsents[it.id]?.takeIf { value ->
                value.expiresAt > now
            }
            mapOf(
                "id" to it.id,
                "nickname" to it.nickname,
                "lastSeen" to it.lastSeen,
                "secure" to noiseSessions.isEstablished(it.id),
                "supportsTransfers" to it.supportsTransfers,
                "role" to it.role.wireName,
                "radarAllowedUntil" to (consent?.expiresAt ?: 0L),
                "radarConsentSource" to consent?.source,
            )
        }
    }

    fun panicWipe() {
        stop()
        storeForward.clear()
        syncPackets.clear()
        identity.clear()
        emit(mapOf("type" to "wiped"))
    }

    /**
     * Radar de rescate: emite lecturas RSSI del peer objetivo. Combina dos
     * fuentes: los anuncios BLE captados por el escaneo (que sigue activo
     * mientras la malla corre) y lecturas periódicas sobre la conexión GATT
     * si el vecino está conectado (único camino con iOS en segundo plano).
     */
    fun startRadar(peerIdHex: String) {
        val normalized = peerIdHex.lowercase()
        check(isRadarAllowed(normalized)) {
            context.getString(R.string.error_radar_consent_required)
        }
        radarPeerId = normalized
        mainHandler.removeCallbacks(radarReadTask)
        startScanning(aggressive = true)
        sendAnnouncement()
        mainHandler.post(radarReadTask)
    }

    fun stopRadar() {
        val wasActive = radarPeerId != null
        radarPeerId = null
        mainHandler.removeCallbacks(radarReadTask)
        tentativeRadarReads.clear()
        if (wasActive && running) startScanning(aggressive = false)
    }

    private val radarReadTask = object : Runnable {
        @SuppressLint("MissingPermission")
        override fun run() {
            val target = radarPeerId ?: return
            if (!isRadarAllowed(target)) {
                stopRadar()
                emit(mapOf("type" to "radarExpired", "peerId" to target))
                return
            }
            val mapped = clientGatts.filterKeys { addressToPeer[it] == target }
            if (mapped.isNotEmpty()) {
                mapped.forEach { (address, gatt) ->
                    tentativeRadarReads.remove(address)
                    runCatching { gatt.readRemoteRssi() }
                }
            } else {
                // iOS no incluye peerId en el anuncio BLE. Si queda una sola
                // conexión GATT lista y sin resolver, úsala como señal
                // tentativa hasta recibir el ANNOUNCE directo.
                val unresolved = clientGatts.filterKeys { address ->
                    clientReady.contains(address) && !addressToPeer.containsKey(address)
                }
                if (unresolved.size == 1) {
                    val (address, gatt) = unresolved.entries.single()
                    tentativeRadarReads[address] = target
                    val started = runCatching { gatt.readRemoteRssi() }.getOrDefault(false)
                    if (!started) tentativeRadarReads.remove(address)
                }
            }
            mainHandler.postDelayed(this, RADAR_READ_INTERVAL_MS)
        }
    }

    private fun emitRssi(peerIdHex: String, rssi: Int, tentative: Boolean = false) {
        emit(
            mapOf(
                "type" to "rssi",
                "peerId" to peerIdHex,
                "rssi" to rssi,
                "tentative" to tentative,
                "at" to System.currentTimeMillis(),
            ),
        )
    }

    private fun sendAnnouncement() {
        if (!running) return
        val payload = MeshProtocol.encodeAnnouncement(
            nickname,
            identity.noisePublicKey,
            identity.signingPublicKey,
        )
        val packet = identity.sign(
            MeshProtocol.Packet(
                type = MeshProtocol.TYPE_ANNOUNCE,
                ttl = MeshProtocol.TTL,
                timestamp = System.currentTimeMillis(),
                senderId = identity.peerId,
                payload = payload,
            ),
        )
        broadcast(packet)
        broadcastHbtCapability()
        sendNodeCapability()
        if (activeLocalRadarConsentUntil() > System.currentTimeMillis()) {
            broadcastRadarConsent(grant = true)
        }
    }

    private fun broadcastHbtCapability() {
        if (!running) return
        broadcast(
            identity.sign(
                MeshProtocol.Packet(
                    type = MeshProtocol.TYPE_HBT_CAPABILITY,
                    ttl = MeshProtocol.TTL,
                    timestamp = System.currentTimeMillis(),
                    senderId = identity.peerId,
                    payload = byteArrayOf(MeshProtocol.HBT_VERSION),
                ),
            ),
        )
    }

    private fun sendNodeCapability() {
        if (!running) return
        broadcast(
            identity.sign(
                MeshProtocol.Packet(
                    type = MeshProtocol.TYPE_NODE_CAPABILITY,
                    ttl = MeshProtocol.TTL,
                    timestamp = System.currentTimeMillis(),
                    senderId = identity.peerId,
                    payload = NodeCapabilityProtocol.encode(localRole),
                ),
            ),
        )
    }

    private fun broadcastRadarConsent(grant: Boolean) {
        if (!running) return
        val expiresAt = if (grant) activeLocalRadarConsentUntil() else 0L
        if (grant && expiresAt <= System.currentTimeMillis()) return
        val packet = identity.sign(
            MeshProtocol.Packet(
                type = MeshProtocol.TYPE_RADAR_CONTROL,
                ttl = 1,
                timestamp = System.currentTimeMillis(),
                senderId = identity.peerId,
                payload = if (grant) {
                    RadarConsentProtocol.grant(expiresAt)
                } else {
                    RadarConsentProtocol.revoke()
                },
            ),
        )
        broadcast(packet)
    }

    private fun activeLocalRadarConsentUntil(): Long {
        val expiresAt = identity.radarConsentUntil
        if (expiresAt <= System.currentTimeMillis()) {
            if (expiresAt != 0L) identity.radarConsentUntil = 0L
            return 0L
        }
        return expiresAt
    }

    private fun isRadarAllowed(peerIdHex: String, now: Long = System.currentTimeMillis()): Boolean {
        val consent = remoteRadarConsents[peerIdHex] ?: return false
        if (consent.expiresAt <= now) {
            remoteRadarConsents.remove(peerIdHex, consent)
            return false
        }
        return true
    }

    private fun pruneRadarConsents(now: Long) {
        remoteRadarConsents.entries.removeIf { it.value.expiresAt <= now }
        val target = radarPeerId
        if (target != null && !isRadarAllowed(target, now)) stopRadar()
    }

    private fun emitRadarConsent() {
        emit(
            mapOf(
                "type" to "radarConsent",
                "radarConsentUntil" to activeLocalRadarConsentUntil(),
                "peers" to peersSnapshot(),
            ),
        )
    }

    private fun requestMissingMessages(peerIdHex: String, sourceAddress: String) {
        val now = System.currentTimeMillis()
        val previous = lastSyncRequestByAddress[sourceAddress]
        if (previous != null && now - previous < SYNC_REQUEST_COOLDOWN_MS) return
        lastSyncRequestByAddress[sourceAddress] = now
        val gcsFilter = MeshProtocol.encodeSyncRequest(syncSnapshot(now))
        val packet = identity.sign(
            MeshProtocol.Packet(
                type = MeshProtocol.TYPE_REQUEST_SYNC,
                ttl = 0,
                timestamp = now,
                senderId = identity.peerId,
                recipientId = peerIdHex.hexToBytes(),
                payload = gcsFilter,
            ),
        )
        Log.i(LOG_TAG, "REQUEST_SYNC sent to ${peerIdHex.take(8)}")
        sendBytesToAddress(MeshProtocol.encodeForBle(packet), sourceAddress)
    }

    private fun initiateHandshake(peerIdHex: String) {
        val peerBytes = peerIdHex.hexToBytes()
        val first = runCatching { noiseSessions.initiate(peerIdHex) }.getOrElse {
            emitError(context.getString(R.string.error_private_channel, it.message))
            return
        } ?: return
        sendNoisePacket(MeshProtocol.TYPE_NOISE_HANDSHAKE, peerBytes, first)
    }

    private fun sendEncryptedPrivate(peerIdHex: String, id: String, content: String) {
        val privateData = MeshProtocol.encodePrivateMessage(id, content)
        val typedPayload = byteArrayOf(MeshProtocol.NOISE_PRIVATE_MESSAGE) + privateData
        val encrypted = runCatching { noiseSessions.encrypt(peerIdHex, typedPayload) }.getOrElse {
            emitError(context.getString(R.string.error_private_encrypt))
            return
        }
        val packet = sendNoisePacket(
            MeshProtocol.TYPE_NOISE_ENCRYPTED,
            peerIdHex.hexToBytes(),
            encrypted,
        )
        depositCourierWithDirectAnchors(packet)
    }

    private fun sendNoisePacket(
        type: Byte,
        recipient: ByteArray,
        payload: ByteArray,
    ): MeshProtocol.Packet {
        val packet = MeshProtocol.Packet(
            type = type,
            ttl = MeshProtocol.TTL,
            timestamp = System.currentTimeMillis(),
            senderId = identity.peerId,
            recipientId = recipient,
            payload = payload,
        )
        broadcast(packet)
        return packet
    }

    private fun depositCourierWithDirectAnchors(innerPacket: MeshProtocol.Packet) {
        val directPeerIds = addressToPeer.values.toSet()
        peers.values
            .filter { it.role == MeshNodeRole.INFRA_DATA_ANCHOR && it.id in directPeerIds }
            .forEach { anchor ->
                if (noiseSessions.isEstablished(anchor.id)) {
                    sendCourierDeposit(anchor.id, innerPacket)
                } else {
                    pendingCourier.computeIfAbsent(anchor.id) {
                        Collections.synchronizedList(mutableListOf())
                    }.add(innerPacket)
                    initiateHandshake(anchor.id)
                }
            }
    }

    private fun sendCourierDeposit(anchorId: String, innerPacket: MeshProtocol.Packet) {
        val recipientId = innerPacket.recipientId ?: return
        val recipient = peers[MeshProtocol.hex(recipientId)] ?: return
        val sourceAddress = addressToPeer.entries.firstOrNull { it.value == anchorId }?.key ?: return
        val payload = runCatching {
            MeshProtocol.encodeCourierEnvelope(
                recipient.noisePublicKey,
                MeshProtocol.encode(innerPacket, padded = false),
            )
        }.getOrNull() ?: return
        val courier = identity.sign(
            MeshProtocol.Packet(
                type = MeshProtocol.TYPE_COURIER_ENVELOPE,
                ttl = MeshProtocol.TTL,
                timestamp = System.currentTimeMillis(),
                senderId = identity.peerId,
                recipientId = anchorId.hexToBytes(),
                payload = payload,
            ),
        )
        sendBytesToAddress(MeshProtocol.encodeForBle(courier), sourceAddress)
        Log.i(LOG_TAG, "Courier deposited with anchor ${anchorId.take(8)}")
    }

    private fun broadcast(packet: MeshProtocol.Packet, excludeAddress: String? = null) {
        rememberSyncPacket(packet)
        val bytes = MeshProtocol.encodeForBle(packet)
        broadcastBytes(bytes, excludeAddress)
        if (localRole.storesDirectedPackets &&
            packet.type != MeshProtocol.TYPE_REQUEST_SYNC &&
            packet.recipientId != null &&
            !packet.recipientId.contentEquals(MeshProtocol.broadcastRecipient)
        ) {
            storeForward.put(packet)
        }
    }

    @SuppressLint("MissingPermission")
    private fun broadcastBytes(bytes: ByteArray, excludeAddress: String?) {
        val characteristic = serverCharacteristic
        val server = gattServer
        if (characteristic != null && server != null) {
            serverSubscribers
                .filterNot { it.address == excludeAddress }
                .forEach { device ->
                    val maximumSize = serverMaximumGattValueSizes[device.address]
                        ?: DEFAULT_GATT_VALUE_SIZE
                    val frames = packetFragmenter.prepare(bytes, maximumSize)
                    if (frames == null) {
                        Log.w(
                            LOG_TAG,
                            "Dropping ${bytes.size}-byte server packet for " +
                                "${device.address.takeLast(5)} (limit=$maximumSize)",
                        )
                    } else {
                        enqueueServerNotifications(device, server, characteristic, frames)
                    }
                }
        }
        clientCharacteristics.forEach { (address, remoteCharacteristic) ->
            if (address != excludeAddress) {
                val gatt = clientGatts[address] ?: return@forEach
                val maximumSize = clientMaximumGattValueSizes[address] ?: DEFAULT_GATT_VALUE_SIZE
                val frames = packetFragmenter.prepare(bytes, maximumSize)
                if (frames == null) {
                    Log.w(
                        LOG_TAG,
                        "Dropping ${bytes.size}-byte client packet for " +
                            "${address.takeLast(5)} (limit=$maximumSize)",
                    )
                } else {
                    enqueueClientWrites(address, gatt, remoteCharacteristic, frames)
                }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun enqueueClientWrites(
        address: String,
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
        frames: List<ByteArray>,
    ) {
        if (frames.isEmpty()) return
        val shouldStart = synchronized(clientWriteLock) {
            val queue = clientWriteQueues.getOrPut(address) { ArrayDeque() }
            if (queue.size + frames.size > MAX_PENDING_GATT_WRITES) {
                Log.w(LOG_TAG, "Client GATT queue full for ${address.takeLast(5)}")
                return
            }
            frames.forEach { queue.addLast(it.copyOf()) }
            clientReady.contains(address) && clientWritesInFlight.add(address)
        }
        if (shouldStart) writeNextClient(address, gatt, characteristic)
    }

    private fun markClientReady(
        address: String,
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ) {
        clientReady.add(address)
        val shouldStart = synchronized(clientWriteLock) {
            clientWriteQueues[address]?.isNotEmpty() == true &&
                clientWritesInFlight.add(address)
        }
        if (shouldStart) writeNextClient(address, gatt, characteristic)
    }

    @SuppressLint("MissingPermission")
    private fun writeNextClient(
        address: String,
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ) {
        val next = synchronized(clientWriteLock) {
            clientWriteQueues[address]?.firstOrNull()
        }
        if (next == null) {
            synchronized(clientWriteLock) { clientWritesInFlight.remove(address) }
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
            completeClientWrite(address, gatt, characteristic)
        }
    }

    private fun completeClientWrite(
        address: String,
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ) {
        synchronized(clientWriteLock) {
            clientWriteQueues[address]?.let { queue ->
                if (queue.isNotEmpty()) queue.removeFirst()
                if (queue.isEmpty()) clientWriteQueues.remove(address)
            }
        }
        writeNextClient(address, gatt, characteristic)
    }

    @SuppressLint("MissingPermission")
    private fun enqueueServerNotifications(
        device: BluetoothDevice,
        server: BluetoothGattServer,
        characteristic: BluetoothGattCharacteristic,
        frames: List<ByteArray>,
    ) {
        if (frames.isEmpty()) return
        val address = device.address
        val shouldStart = synchronized(serverNotificationLock) {
            val queue = serverNotificationQueues.getOrPut(address) { ArrayDeque() }
            if (queue.size + frames.size > MAX_PENDING_GATT_WRITES) {
                Log.w(LOG_TAG, "Server GATT queue full for ${address.takeLast(5)}")
                return
            }
            frames.forEach { queue.addLast(it.copyOf()) }
            serverNotificationsInFlight.add(address)
        }
        if (shouldStart) writeNextServerNotification(device, server, characteristic)
    }

    @SuppressLint("MissingPermission")
    private fun writeNextServerNotification(
        device: BluetoothDevice,
        server: BluetoothGattServer,
        characteristic: BluetoothGattCharacteristic,
    ) {
        val address = device.address
        val next = synchronized(serverNotificationLock) {
            serverNotificationQueues[address]?.firstOrNull()
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
            completeServerNotification(device, server, characteristic)
        }
    }

    private fun completeServerNotification(
        device: BluetoothDevice,
        server: BluetoothGattServer,
        characteristic: BluetoothGattCharacteristic,
    ) {
        val address = device.address
        synchronized(serverNotificationLock) {
            serverNotificationQueues[address]?.let { queue ->
                if (queue.isNotEmpty()) queue.removeFirst()
                if (queue.isEmpty()) serverNotificationQueues.remove(address)
            }
        }
        writeNextServerNotification(device, server, characteristic)
    }

    private fun receive(bytes: ByteArray, sourceAddress: String) {
        Log.d(
            LOG_TAG,
            "RX address=${sourceAddress.takeLast(5)} bytes=${bytes.size} " +
                "prefix=${MeshProtocol.hex(bytes.copyOfRange(0, minOf(bytes.size, 24)))}",
        )
        val packet = MeshProtocol.decode(bytes)
        if (packet == null) {
            Log.w(LOG_TAG, "RX rejected: packet decode failed (${bytes.size} bytes)")
            return
        }
        val senderHex = MeshProtocol.hex(packet.senderId)
        Log.d(
            LOG_TAG,
            "RX decoded: version=${packet.version} type=${packet.type.toUByte()} " +
                "ttl=${packet.ttl.toUByte()} sender=${senderHex.take(8)}",
        )
        val fingerprint = MeshProtocol.fingerprint(packet)
        if (seen.put(fingerprint, System.currentTimeMillis()) != null) return
        if (senderHex == peerId) return

        val isForUs = packet.recipientId == null ||
            packet.recipientId.contentEquals(identity.peerId) ||
            packet.recipientId.contentEquals(MeshProtocol.broadcastRecipient)
        if (isForUs) process(packet, senderHex, sourceAddress)

        val addressedToLocalNode = packet.recipientId?.contentEquals(identity.peerId) == true
        if (MeshRelayPolicy.shouldRelay(
                role = localRole,
                packetType = packet.type,
                ttl = packet.ttl.toInt() and 0xFF,
                addressedToLocalNode = addressedToLocalNode,
            )
        ) {
            val relayed = packet.copy(ttl = ((packet.ttl.toInt() and 0xFF) - 1).toByte())
            broadcastBytes(MeshProtocol.encodeForBle(relayed), sourceAddress)
        }
    }

    private fun process(
        packet: MeshProtocol.Packet,
        senderHex: String,
        sourceAddress: String,
    ) {
        when (packet.type) {
            MeshProtocol.TYPE_ANNOUNCE -> processAnnouncement(packet, senderHex, sourceAddress)
            MeshProtocol.TYPE_MESSAGE -> processPublicMessage(packet, senderHex)
            MeshProtocol.TYPE_NOISE_HANDSHAKE -> processHandshake(packet, senderHex)
            MeshProtocol.TYPE_NOISE_ENCRYPTED -> processEncrypted(packet, senderHex)
            MeshProtocol.TYPE_COURIER_ENVELOPE -> processCourier(packet, senderHex)
            MeshProtocol.TYPE_REQUEST_SYNC -> processSyncRequest(packet, senderHex, sourceAddress)
            MeshProtocol.TYPE_RADAR_CONTROL -> processRadarControl(packet, senderHex)
            MeshProtocol.TYPE_HBT_CAPABILITY -> processHbtCapability(packet, senderHex)
            MeshProtocol.TYPE_NODE_CAPABILITY -> processNodeCapability(packet, senderHex)
            MeshProtocol.TYPE_FRAGMENT -> {
                val reassembled = fragmentReassembler.accept(packet)
                if (reassembled != null) {
                    Log.i(
                        LOG_TAG,
                        "FRAGMENT reassembled: type=${reassembled.type.toUByte()} " +
                            "sender=${senderHex.take(8)} bytes=${reassembled.payload.size}",
                    )
                    process(reassembled, senderHex, sourceAddress)
                }
            }
        }
    }

    private fun processAnnouncement(
        packet: MeshProtocol.Packet,
        senderHex: String,
        sourceAddress: String,
    ) {
        val announcement = MeshProtocol.decodeAnnouncement(packet.payload)
        if (announcement == null) {
            Log.w(
                LOG_TAG,
                "ANNOUNCE rejected from ${senderHex.take(8)}: payload decode failed " +
                    "(${packet.payload.size} bytes)",
            )
            return
        }
        if (!MeshProtocol.peerIdFromNoiseKey(announcement.noisePublicKey)
                .contentEquals(packet.senderId)
        ) {
            Log.w(
                LOG_TAG,
                "ANNOUNCE rejected from ${senderHex.take(8)}: Noise key does not match peerId",
            )
            return
        }
        if (!identity.verify(packet, announcement.signingPublicKey)) {
            Log.w(
                LOG_TAG,
                "ANNOUNCE rejected from ${senderHex.take(8)}: Ed25519 signature invalid",
            )
            return
        }
        Log.i(
            LOG_TAG,
            "ANNOUNCE accepted from ${senderHex.take(8)} nickname=${announcement.nickname}",
        )
        // Solo vincular dirección y peerId después de validar claves y firma.
        // TTL intacto prueba que el anuncio llegó directamente, no por relay.
        if (packet.ttl == MeshProtocol.TTL) {
            addressToPeer[sourceAddress] = senderHex
        }
        val previouslySupported = peers[senderHex]?.supportsTransfers == true
        val previousRole = peers[senderHex]?.role ?: if (announcement.isInfrastructure) {
            MeshNodeRole.INFRA_DATA_ANCHOR
        } else {
            MeshNodeRole.PHONE_RELAY
        }
        peers[senderHex] = Peer(
            senderHex,
            announcement.nickname,
            announcement.signingPublicKey,
            announcement.noisePublicKey,
            announcement.supportsTransfers || previouslySupported,
            previousRole,
        )
        rememberSyncPacket(packet)
        emit(mapOf("type" to "peers", "peers" to peersSnapshot()))
        requestMissingMessages(senderHex, sourceAddress)
        storeForward.forRecipient(packet.senderId).forEach(::broadcast)
        if (pendingPrivate[senderHex]?.isNotEmpty() == true ||
            pendingFrames[senderHex]?.isNotEmpty() == true ||
            pendingCourier[senderHex]?.isNotEmpty() == true
        ) {
            initiateHandshake(senderHex)
        }
    }

    private fun processHbtCapability(packet: MeshProtocol.Packet, senderHex: String) {
        val peer = peers[senderHex] ?: return
        if (packet.payload.size != 1 || packet.payload[0] != MeshProtocol.HBT_VERSION) return
        if (!identity.verify(packet, peer.signingPublicKey)) return
        peer.supportsTransfers = true
        peer.lastSeen = System.currentTimeMillis()
        emit(mapOf("type" to "peers", "peers" to peersSnapshot()))
    }

    private fun processNodeCapability(packet: MeshProtocol.Packet, senderHex: String) {
        val peer = peers[senderHex] ?: return
        val capability = NodeCapabilityProtocol.decode(packet.payload) ?: return
        if (!identity.verify(packet, peer.signingPublicKey)) return
        peer.role = capability.role
        peer.lastSeen = System.currentTimeMillis()
        emit(mapOf("type" to "peers", "peers" to peersSnapshot()))
    }

    private fun processPublicMessage(packet: MeshProtocol.Packet, senderHex: String) {
        val peer = peers[senderHex]
        if (peer == null) {
            Log.w(LOG_TAG, "MESSAGE rejected from ${senderHex.take(8)}: peer not announced")
            return
        }
        if (!identity.verify(packet, peer.signingPublicKey)) {
            Log.w(LOG_TAG, "MESSAGE rejected from ${senderHex.take(8)}: signature invalid")
            return
        }
        val message = MeshProtocol.decodeCompatiblePublicMessage(
            payload = packet.payload,
            id = MeshProtocol.fingerprint(packet).uppercase(),
            sender = peer.nickname,
            timestamp = packet.timestamp,
            senderPeerId = senderHex,
        )
        rememberSyncPacket(packet)
        peer.lastSeen = System.currentTimeMillis()
        if (message.channel == "sos") {
            val expiresAt = packet.timestamp + RadarConsentProtocol.SOS_DURATION_MS
            if (expiresAt > System.currentTimeMillis()) {
                remoteRadarConsents[senderHex] = RemoteRadarConsent(expiresAt, "sos")
                emit(mapOf("type" to "peers", "peers" to peersSnapshot()))
            }
        }
        emitMessage(
            message.id,
            message.sender,
            message.content,
            senderHex,
            false,
            false,
            message.timestamp,
            message.channel,
        )
    }

    private fun processRadarControl(packet: MeshProtocol.Packet, senderHex: String) {
        val peer = peers[senderHex] ?: return
        if (!identity.verify(packet, peer.signingPublicKey)) return
        val consent = RadarConsentProtocol.decode(packet.payload) ?: return
        if (!RadarConsentProtocol.hasValidTimestamp(packet.timestamp)) return
        if (consent.action == RadarConsentProtocol.ACTION_REVOKE) {
            remoteRadarConsents.remove(senderHex)
            if (radarPeerId == senderHex) stopRadar()
        } else if (RadarConsentProtocol.isValidGrant(consent, packet.timestamp)) {
            remoteRadarConsents[senderHex] =
                RemoteRadarConsent(consent.expiresAt, "temporary")
        } else {
            return
        }
        emit(mapOf("type" to "peers", "peers" to peersSnapshot()))
    }

    private fun processHandshake(packet: MeshProtocol.Packet, senderHex: String) {
        val result = runCatching {
            noiseSessions.process(senderHex, packet.senderId, packet.payload)
        }.getOrElse { error ->
            if (error is NoiseHandshakeFailure.IdentityMismatch) {
                emitError(context.getString(R.string.error_identity_rejected))
            } else {
                Log.w(
                    LOG_TAG,
                    "Noise handshake state/protocol failure from ${senderHex.take(8)}",
                    error,
                )
            }
            return
        }
        if (result.response != null) {
            sendNoisePacket(MeshProtocol.TYPE_NOISE_HANDSHAKE, packet.senderId, result.response)
        }
        if (result.establishedNow) {
            emit(mapOf("type" to "peers", "peers" to peersSnapshot()))
            pendingPrivate.remove(senderHex)?.forEach {
                sendEncryptedPrivate(senderHex, it.id, it.content)
            }
            pendingFrames.remove(senderHex)?.forEach {
                sendEncryptedFrame(senderHex, it)
            }
            pendingCourier.remove(senderHex)?.forEach {
                sendCourierDeposit(senderHex, it)
            }
        }
    }

    private fun processEncrypted(packet: MeshProtocol.Packet, senderHex: String) {
        if (!noiseSessions.isEstablished(senderHex)) return
        val plaintext = runCatching { noiseSessions.decrypt(senderHex, packet.payload) }
            .getOrElse { return }
        if (plaintext.isEmpty()) return
        if (plaintext[0] == MeshProtocol.NOISE_TRANSFER_FRAME) {
            emit(
                mapOf(
                    "type" to "transferFrame",
                    "peerId" to senderHex,
                    "frame" to plaintext.copyOfRange(1, plaintext.size),
                ),
            )
            return
        }
        if (plaintext[0] != MeshProtocol.NOISE_PRIVATE_MESSAGE) return
        val message = MeshProtocol.decodePrivateMessage(plaintext.copyOfRange(1, plaintext.size))
            ?: return
        emitMessage(
            message.id,
            peers[senderHex]?.nickname ?: senderHex.take(8),
            message.content,
            senderHex,
            true,
            false,
            packet.timestamp,
            null,
        )
    }

    private fun processCourier(packet: MeshProtocol.Packet, senderHex: String) {
        val carrier = peers[senderHex] ?: return
        if (!identity.verify(packet, carrier.signingPublicKey)) return
        val envelope = MeshProtocol.decodeCourierEnvelope(packet.payload) ?: return
        if (!MeshProtocol.courierEnvelopeIsFor(envelope, identity.noisePublicKey)) return
        val inner = MeshProtocol.decode(envelope.ciphertext) ?: return
        if (inner.type != MeshProtocol.TYPE_NOISE_ENCRYPTED ||
            inner.recipientId?.contentEquals(identity.peerId) != true
        ) {
            return
        }
        val fingerprint = MeshProtocol.fingerprint(inner)
        if (seen.put(fingerprint, System.currentTimeMillis()) != null) return
        processEncrypted(inner, MeshProtocol.hex(inner.senderId))
    }

    private fun processSyncRequest(
        packet: MeshProtocol.Packet,
        senderHex: String,
        sourceAddress: String,
    ) {
        if (packet.ttl != 0.toByte() || !allowSyncResponse(sourceAddress)) return
        val peer = peers[senderHex] ?: return
        if (!identity.verify(packet, peer.signingPublicKey)) return
        val request = MeshProtocol.decodeSyncRequest(packet.payload) ?: return
        val remoteBuckets = MeshProtocol.decodeGcs(request)
        var sent = 0
        syncSnapshot().forEach { candidate ->
            if (sent >= SYNC_MAX_REPLAY) return@forEach
            val typeFlag = when (candidate.type) {
                MeshProtocol.TYPE_ANNOUNCE -> MeshProtocol.SYNC_FLAG_ANNOUNCE
                MeshProtocol.TYPE_MESSAGE -> MeshProtocol.SYNC_FLAG_MESSAGE
                else -> 0L
            }
            if (request.typeFlags and typeFlag == 0L) return@forEach
            if (request.since != null &&
                candidate.type != MeshProtocol.TYPE_ANNOUNCE &&
                candidate.timestamp < request.since
            ) {
                return@forEach
            }
            val bucket = MeshProtocol.gcsBucket(MeshProtocol.packetId(candidate), request.m)
            if (remoteBuckets.isNotEmpty() && MeshProtocol.gcsContains(remoteBuckets, bucket)) {
                return@forEach
            }
            sendBytesToAddress(
                MeshProtocol.encodeForBle(candidate.copy(ttl = 0, isRsr = true)),
                sourceAddress,
            )
            sent++
        }
        if (sent > 0) Log.i(LOG_TAG, "REQUEST_SYNC replayed $sent packet(s)")
    }

    private fun allowSyncResponse(sourceAddress: String): Boolean {
        val now = System.currentTimeMillis()
        val timestamps = syncResponseTimes.computeIfAbsent(sourceAddress) { ArrayDeque() }
        synchronized(timestamps) {
            while (timestamps.isNotEmpty() && now - timestamps.first() > SYNC_RATE_WINDOW_MS) {
                timestamps.removeFirst()
            }
            if (timestamps.size >= SYNC_RATE_MAX_RESPONSES) return false
            timestamps.addLast(now)
            return true
        }
    }

    private fun rememberSyncPacket(packet: MeshProtocol.Packet) {
        if (packet.signature == null ||
            packet.type !in setOf(MeshProtocol.TYPE_ANNOUNCE, MeshProtocol.TYPE_MESSAGE) ||
            packet.recipientId?.contentEquals(MeshProtocol.broadcastRecipient) == false
        ) {
            return
        }
        val now = System.currentTimeMillis()
        if (!isSyncFresh(packet, now) || packet.timestamp > now + SYNC_FUTURE_SKEW_MS) return
        synchronized(syncPackets) {
            if (packet.type == MeshProtocol.TYPE_ANNOUNCE) {
                val sender = MeshProtocol.hex(packet.senderId)
                if (syncPackets.values.any {
                        it.type == MeshProtocol.TYPE_ANNOUNCE &&
                            MeshProtocol.hex(it.senderId) == sender &&
                            it.timestamp >= packet.timestamp
                    }
                ) {
                    return
                }
                val superseded = syncPackets.filterValues {
                    it.type == MeshProtocol.TYPE_ANNOUNCE &&
                        MeshProtocol.hex(it.senderId) == sender &&
                        it.timestamp <= packet.timestamp
                }.keys
                superseded.forEach(syncPackets::remove)
            }
            syncPackets[MeshProtocol.hex(MeshProtocol.packetId(packet))] = packet
        }
    }

    private fun syncSnapshot(now: Long = System.currentTimeMillis()): List<MeshProtocol.Packet> =
        synchronized(syncPackets) {
            val expired = syncPackets.filterValues { !isSyncFresh(it, now) }.keys
            expired.forEach(syncPackets::remove)
            syncPackets.values.sortedByDescending { it.timestamp }
        }

    private fun isSyncFresh(packet: MeshProtocol.Packet, now: Long): Boolean {
        val window = if (packet.type == MeshProtocol.TYPE_ANNOUNCE) {
            SYNC_ANNOUNCE_WINDOW_MS
        } else {
            SYNC_MESSAGE_WINDOW_MS
        }
        return now < window || packet.timestamp >= now - window
    }

    @SuppressLint("MissingPermission")
    private fun sendBytesToAddress(bytes: ByteArray, address: String) {
        clientCharacteristics[address]?.let { characteristic ->
            val gatt = clientGatts[address] ?: return@let
            val maximumSize = clientMaximumGattValueSizes[address] ?: DEFAULT_GATT_VALUE_SIZE
            packetFragmenter.prepare(bytes, maximumSize)?.let { frames ->
                enqueueClientWrites(address, gatt, characteristic, frames)
            } ?: Log.w(
                LOG_TAG,
                "Dropping ${bytes.size}-byte client packet for " +
                    "${address.takeLast(5)} (limit=$maximumSize)",
            )
        }
        val subscriber = serverSubscribers.firstOrNull { it.address == address } ?: return
        val server = gattServer ?: return
        val characteristic = serverCharacteristic ?: return
        val maximumSize = serverMaximumGattValueSizes[address] ?: DEFAULT_GATT_VALUE_SIZE
        packetFragmenter.prepare(bytes, maximumSize)?.let { frames ->
            enqueueServerNotifications(subscriber, server, characteristic, frames)
        } ?: Log.w(
            LOG_TAG,
            "Dropping ${bytes.size}-byte server packet for " +
                "${address.takeLast(5)} (limit=$maximumSize)",
        )
    }

    @SuppressLint("MissingPermission")
    private fun startGattServer() {
        val characteristic = BluetoothGattCharacteristic(
            CHARACTERISTIC_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or
                BluetoothGattCharacteristic.PROPERTY_WRITE or
                BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ or
                BluetoothGattCharacteristic.PERMISSION_WRITE,
        )
        characteristic.addDescriptor(
            BluetoothGattDescriptor(
                CLIENT_CONFIGURATION_UUID,
                BluetoothGattDescriptor.PERMISSION_READ or
                    BluetoothGattDescriptor.PERMISSION_WRITE,
            ),
        )
        val service = BluetoothGattService(
            SERVICE_UUID,
            BluetoothGattService.SERVICE_TYPE_PRIMARY,
        )
        service.addCharacteristic(characteristic)
        serverCharacteristic = characteristic
        gattServer = bluetoothManager.openGattServer(context, serverCallback).also {
            it.addService(service)
        }
    }

    @SuppressLint("MissingPermission")
    private fun startAdvertising() {
        val advertiser = adapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            emitError(context.getString(R.string.error_no_advertising))
            emitStatus("degraded")
            return
        }
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(localRole != MeshNodeRole.PHONE_BEACON)
            .build()
        // El PDU legado de BLE admite 31 bytes. UUID (18B + banderas) viaja en
        // el anuncio principal y el peerId (26B con cabeceras) en la respuesta
        // de escaneo, igual que BitChat. Ver MeshAdvertisePlan.
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        val scanResponse = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceData(ParcelUuid(SERVICE_UUID), identity.peerId)
            .build()
        val generation = ++advertiseGeneration
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                if (!running || generation != advertiseGeneration) return
                cancelAdvertiseWatchdog()
                advertising = true
                advertiseAttempt = 0
                emitStatus("active")
                sendAnnouncement()
            }

            override fun onStartFailure(errorCode: Int) {
                if (!running || generation != advertiseGeneration) return
                cancelAdvertiseWatchdog()
                advertising = false
                emitError(context.getString(R.string.error_advertise_failed, errorCode))
                emitStatus("degraded")
            }
        }
        advertiseCallback = callback
        advertiser.startAdvertising(settings, data, scanResponse, callback)
        scheduleAdvertiseWatchdog(generation)
    }

    @SuppressLint("MissingPermission")
    private fun startScanning(aggressive: Boolean = false) {
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build()
        val settingsBuilder = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
        if (aggressive) {
            settingsBuilder
                .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
                .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
        }
        val settings = settingsBuilder.build()
        runCatching { adapter.bluetoothLeScanner?.stopScan(scanCallback) }
        adapter.bluetoothLeScanner?.startScan(listOf(filter), settings, scanCallback)
    }

    /**
     * Segundo nivel: presencia BLE genérica. Se escanea sin filtro, pero no se
     * conecta al dispositivo ni se leen nombre o MAC. Solo se publican IDs
     * locales rotativos producidos por [GenericBlePresenceTracker].
     */
    @SuppressLint("MissingPermission")
    private fun startGenericBeaconScanning() {
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_POWER)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .build()
        runCatching { adapter.bluetoothLeScanner?.stopScan(genericBeaconScanCallback) }
        adapter.bluetoothLeScanner?.startScan(
            emptyList(),
            settings,
            genericBeaconScanCallback,
        )
    }

    @SuppressLint("MissingPermission")
    private fun scheduleAdvertiseWatchdog(generation: Int) {
        cancelAdvertiseWatchdog()
        advertiseWatchdog = Runnable {
            if (!running || advertising || generation != advertiseGeneration) return@Runnable
            val callback = advertiseCallback
            if (callback != null) {
                runCatching { adapter.bluetoothLeAdvertiser?.stopAdvertising(callback) }
            }
            advertiseCallback = null
            if (advertiseAttempt < MAX_ADVERTISE_RETRIES) {
                advertiseAttempt += 1
                startAdvertising()
            } else {
                emitError(context.getString(R.string.error_advertise_timeout))
                emitStatus("degraded")
            }
        }.also { mainHandler.postDelayed(it, ADVERTISE_TIMEOUT_MS) }
    }

    private fun cancelAdvertiseWatchdog() {
        advertiseWatchdog?.let(mainHandler::removeCallbacks)
        advertiseWatchdog = null
    }

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            runCatching { handleMeshScanResult(result) }
                .onFailure { Log.w(LOG_TAG, "Ignoring malformed mesh scan result", it) }
        }

        override fun onScanFailed(errorCode: Int) {
            emitError(context.getString(R.string.error_scan_failed, errorCode))
        }
    }

    private val genericBeaconScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            runCatching { handleGenericBeaconScanResult(result) }
                .onFailure { Log.w(LOG_TAG, "Ignoring malformed generic BLE result", it) }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.w(LOG_TAG, "Generic BLE presence scan failed: $errorCode")
        }
    }

    @SuppressLint("MissingPermission")
    private fun handleMeshScanResult(result: ScanResult) {
        val advertisedPeer = result.scanRecord
            ?.getServiceData(ParcelUuid(SERVICE_UUID))
            ?.takeIf { it.size >= 8 }
            ?.copyOfRange(0, 8)
        if (advertisedPeer?.contentEquals(identity.peerId) == true) return
        val address = result.device.address
        if (advertisedPeer != null) {
            addressToPeer[address] = MeshProtocol.hex(advertisedPeer)
        }
        val radarTarget = radarPeerId
        if (radarTarget != null && addressToPeer[address] == radarTarget) {
            emitRssi(radarTarget, result.rssi)
        }
        if (clientGatts.containsKey(address)) return
        clientGatts[address] = result.device.connectGatt(
            context,
            false,
            clientCallback,
            BluetoothDevice.TRANSPORT_LE,
        )
    }

    private fun handleGenericBeaconScanResult(result: ScanResult) {
        val record = result.scanRecord ?: return
        if (isMeshAdvertisement(record)) return
        val changed = genericPresenceTracker.record(
            advertisementMaterial = genericAdvertisementMaterial(record),
            rssi = result.rssi,
            now = System.currentTimeMillis(),
        )
        if (changed) scheduleGenericPresenceEmit()
    }

    private fun handleDirectLinkLost(address: String) {
        val hasClientLink = clientReady.contains(address)
        val hasServerLink = serverSubscribers.any { it.address == address }
        if (hasClientLink || hasServerLink) return
        val disconnectedPeer = addressToPeer.remove(address) ?: return
        if (addressToPeer.values.none { it == disconnectedPeer }) {
            noiseSessions.invalidate(disconnectedPeer)
            emit(mapOf("type" to "peers", "peers" to peersSnapshot()))
        }
    }

    private fun scheduleGenericPresenceEmit() {
        if (genericPresenceEmitRunnable != null) return
        genericPresenceEmitRunnable = Runnable {
            genericPresenceEmitRunnable = null
            if (!running) return@Runnable
            val presences = genericPresenceTracker.snapshot(System.currentTimeMillis())
            emit(
                mapOf(
                    "type" to "presences",
                    "presences" to presences.map(
                        GenericBlePresenceTracker.Presence::toEventMap,
                    ),
                ),
            )
        }.also {
            mainHandler.postDelayed(it, GENERIC_PRESENCE_EMIT_INTERVAL_MS)
        }
    }

    private val clientCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                clientMaximumGattValueSizes.putIfAbsent(
                    gatt.device.address,
                    DEFAULT_GATT_VALUE_SIZE,
                )
                if (!gatt.requestMtu(MeshPacketFragmenter.MAX_ATT_MTU)) gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                clientCharacteristics.remove(gatt.device.address)
                clientGatts.remove(gatt.device.address)
                clientMaximumGattValueSizes.remove(gatt.device.address)
                clientReady.remove(gatt.device.address)
                lastSyncRequestByAddress.remove(gatt.device.address)
                syncResponseTimes.remove(gatt.device.address)
                synchronized(clientWriteLock) {
                    clientWriteQueues.remove(gatt.device.address)
                    clientWritesInFlight.remove(gatt.device.address)
                }
                handleDirectLinkLost(gatt.device.address)
                gatt.close()
            }
        }

        @SuppressLint("MissingPermission")
        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                clientMaximumGattValueSizes[gatt.device.address] =
                    MeshPacketFragmenter.maximumGattValueSize(mtu)
            }
            gatt.discoverServices()
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val characteristic = gatt.getService(SERVICE_UUID)
                ?.getCharacteristic(CHARACTERISTIC_UUID) ?: return
            clientCharacteristics[gatt.device.address] = characteristic
            gatt.setCharacteristicNotification(characteristic, true)
            val descriptor = characteristic.getDescriptor(CLIENT_CONFIGURATION_UUID)
            if (descriptor != null) {
                val descriptorStarted = if (Build.VERSION.SDK_INT >= 33) {
                    gatt.writeDescriptor(
                        descriptor,
                        BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE,
                    ) == BluetoothStatusCodes.SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    @Suppress("DEPRECATION")
                    gatt.writeDescriptor(descriptor)
                }
                if (!descriptorStarted) {
                    markClientReady(gatt.device.address, gatt, characteristic)
                    sendAnnouncement()
                }
            } else {
                markClientReady(gatt.device.address, gatt, characteristic)
                sendAnnouncement()
            }
        }

        override fun onDescriptorWrite(
            gatt: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int,
        ) {
            if (descriptor.uuid == CLIENT_CONFIGURATION_UUID) {
                val characteristic = clientCharacteristics[gatt.device.address] ?: return
                markClientReady(gatt.device.address, gatt, characteristic)
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    Log.w(
                        LOG_TAG,
                        "CCCD write failed for ${gatt.device.address.takeLast(5)}: $status",
                    )
                }
                sendAnnouncement()
            }
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (characteristic.uuid == CHARACTERISTIC_UUID) {
                completeClientWrite(gatt.device.address, gatt, characteristic)
            }
        }

        @Deprecated("Deprecated in Android 13")
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
        ) {
            characteristic.value?.let { receive(it, gatt.device.address) }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            receive(value, gatt.device.address)
        }

        override fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {
            val address = gatt.device.address
            val tentativeTarget = tentativeRadarReads.remove(address)
            if (status != BluetoothGatt.GATT_SUCCESS) return
            val target = radarPeerId ?: return
            if (addressToPeer[address] == target) {
                emitRssi(target, rssi)
            } else if (tentativeTarget == target) {
                emitRssi(target, rssi, tentative = true)
            }
        }
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                serverMaximumGattValueSizes.putIfAbsent(device.address, DEFAULT_GATT_VALUE_SIZE)
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                serverSubscribers.remove(device)
                serverMaximumGattValueSizes.remove(device.address)
                lastSyncRequestByAddress.remove(device.address)
                syncResponseTimes.remove(device.address)
                synchronized(serverNotificationLock) {
                    serverNotificationQueues.remove(device.address)
                    serverNotificationsInFlight.remove(device.address)
                }
                handleDirectLinkLost(device.address)
            }
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            serverMaximumGattValueSizes[device.address] =
                MeshPacketFragmenter.maximumGattValueSize(mtu)
        }

        @SuppressLint("MissingPermission")
        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            if (characteristic.uuid == CHARACTERISTIC_UUID && offset == 0) {
                receive(value, device.address)
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
        }

        @SuppressLint("MissingPermission")
        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray,
        ) {
            if (descriptor.uuid == CLIENT_CONFIGURATION_UUID) {
                if (BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE.contentEquals(value)) {
                    serverSubscribers.add(device)
                    serverMaximumGattValueSizes.putIfAbsent(
                        device.address,
                        DEFAULT_GATT_VALUE_SIZE,
                    )
                } else {
                    serverSubscribers.remove(device)
                }
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
            if (descriptor.uuid == CLIENT_CONFIGURATION_UUID) {
                mainHandler.post { sendAnnouncement() }
            }
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            val server = gattServer ?: return
            val characteristic = serverCharacteristic ?: return
            if (status != BluetoothGatt.GATT_SUCCESS) {
                Log.w(
                    LOG_TAG,
                    "Server notification failed for ${device.address.takeLast(5)}: $status",
                )
            }
            completeServerNotification(device, server, characteristic)
        }
    }

    private fun emitMessage(
        id: String,
        sender: String,
        content: String,
        senderPeerId: String,
        private: Boolean,
        mine: Boolean,
        timestamp: Long,
        channel: String?,
    ) {
        emit(
            mapOf(
                "type" to "message",
                "message" to mapOf(
                    "id" to id,
                    "sender" to sender,
                    "content" to content,
                    "senderPeerId" to senderPeerId,
                    "private" to private,
                    "mine" to mine,
                    "timestamp" to timestamp,
                    "channel" to channel,
                ),
            ),
        )
    }

    private fun emitStatus(status: String) {
        currentStatus = status
        emit(
            mapOf(
                "type" to "status",
                "status" to status,
                "peerId" to peerId,
                "nickname" to nickname,
                "role" to localRole.wireName,
            ),
        )
    }

    private fun emitError(message: String) {
        emit(mapOf("type" to "error", "message" to message))
    }

    private fun String.hexToBytes(): ByteArray {
        require(length == 16)
        return chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }

    private fun isMeshAdvertisement(record: ScanRecord): Boolean {
        val service = ParcelUuid(SERVICE_UUID)
        return record.serviceUuids?.contains(service) == true ||
            record.serviceData.containsKey(service)
    }

    /**
     * Material canónico sin nombre ni dirección. Una baliza sin datos de
     * servicio/fabricante no se puede agrupar de forma privada y se ignora.
     */
    private fun genericAdvertisementMaterial(record: ScanRecord): ByteArray {
        val output = ByteArrayOutputStream()

        fun writeField(tag: Int, key: ByteArray, value: ByteArray = byteArrayOf()) {
            output.write(tag)
            val size = key.size + value.size
            output.write((size ushr 8) and 0xFF)
            output.write(size and 0xFF)
            output.write(key)
            output.write(value)
        }

        record.serviceUuids.orEmpty()
            .map { it.uuid.toString() }
            .sorted()
            .forEach { writeField(0x01, it.toByteArray(Charsets.US_ASCII)) }

        if (Build.VERSION.SDK_INT >= 29) {
            record.serviceSolicitationUuids.orEmpty()
                .map { it.uuid.toString() }
                .sorted()
                .forEach { writeField(0x02, it.toByteArray(Charsets.US_ASCII)) }
        }

        record.serviceData.entries
            .sortedBy { it.key.uuid.toString() }
            .forEach { (uuid, value) ->
                writeField(
                    0x03,
                    uuid.uuid.toString().toByteArray(Charsets.US_ASCII),
                    value,
                )
            }

        val manufacturerData = record.manufacturerSpecificData
        for (index in 0 until manufacturerData.size()) {
            val manufacturerId = manufacturerData.keyAt(index)
            val key = byteArrayOf(
                (manufacturerId ushr 8).toByte(),
                manufacturerId.toByte(),
            )
            writeField(0x04, key, manufacturerData.valueAt(index))
        }

        return output.toByteArray()
    }

    private companion object {
        /** Techo del plano de control BLE; los blobs van por otros transportes. */
        const val MAX_TRANSFER_FRAME = 2_048

        /** Cadencia de lectura RSSI sobre GATT conectado en modo radar. */
        const val RADAR_READ_INTERVAL_MS = 500L

        const val ADVERTISE_TIMEOUT_MS = 10_000L
        const val MAX_ADVERTISE_RETRIES = 1
        const val MAX_PENDING_GATT_WRITES = 256
        const val DEFAULT_GATT_VALUE_SIZE =
            MeshPacketFragmenter.DEFAULT_ATT_MTU - MeshPacketFragmenter.ATT_PROTOCOL_OVERHEAD
        const val SYNC_REQUEST_COOLDOWN_MS = 60_000L
        const val SYNC_STORE_CAPACITY = 80
        const val SYNC_MAX_REPLAY = 40
        const val SYNC_RATE_MAX_RESPONSES = 8
        const val SYNC_RATE_WINDOW_MS = 30_000L
        const val SYNC_ANNOUNCE_WINDOW_MS = 15 * 60 * 1_000L
        const val SYNC_MESSAGE_WINDOW_MS = 6 * 60 * 60 * 1_000L
        const val SYNC_FUTURE_SKEW_MS = 15 * 60 * 1_000L
        const val ROLE_TRANSITION_DELAY_MS = 750L
        const val GENERIC_PRESENCE_EMIT_INTERVAL_MS = 1_000L

        const val LOG_TAG = "HearthBitMesh"

        val SERVICE_UUID: UUID =
            UUID.fromString("F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C")
        val CHARACTERISTIC_UUID: UUID =
            UUID.fromString("A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D")
        val CLIENT_CONFIGURATION_UUID: UUID =
            UUID.fromString("00002902-0000-1000-8000-00805F9B34FB")
    }
}
