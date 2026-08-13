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
    private val observeNotification: (MeshNotificationState) -> Unit,
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
    private val noiseFailureTracker = NoiseFailureRecoveryTracker()
    private val relationshipPreferences = context.getSharedPreferences(
        RELATIONSHIP_PREFERENCES,
        Context.MODE_PRIVATE,
    )
    private val peersWithSessionHistory = ConcurrentHashMap.newKeySet<String>().apply {
        addAll(
            relationshipPreferences.getStringSet(KEY_SESSION_PEERS, emptySet())
                .orEmpty(),
        )
    }
    private val lastHandshakeAttemptByPeer = ConcurrentHashMap<String, Long>()
    private val latestAnnouncementTimestampByPeer = ConcurrentHashMap<String, Long>()
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
    private val knownDevices = ConcurrentHashMap<String, BluetoothDevice>()
    private val reconnectPeerByAddress = ConcurrentHashMap<String, String>()
    private val autoReconnectExpiryByAddress = ConcurrentHashMap<String, Long>()
    private val autoReconnectAddresses = ConcurrentHashMap.newKeySet<String>()
    private val autoReconnectScheduledAddresses = ConcurrentHashMap.newKeySet<String>()
    private val overflowCandidateAddresses = ConcurrentHashMap.newKeySet<String>()
    private val overflowCandidateCooldownUntil = ConcurrentHashMap<String, Long>()
    private val overflowMaskByAddress = ConcurrentHashMap<String, ByteArray>()
    @Volatile
    private var learnedIosOverflowBit = relationshipPreferences
        .getInt(KEY_IOS_OVERFLOW_BIT, -1)
        .takeIf { it in 0 until 128 }
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
    private val pendingBeaconRequests = ConcurrentHashMap<String, PendingBeaconRequest>()
    private val outgoingBeaconRequests = ConcurrentHashMap<String, OutgoingBeaconRequest>()
    private val seenBeaconActions = ConcurrentHashMap<String, Long>()
    private val beaconActuator = BeaconActuator(context)
    private val tentativeRadarReads = ConcurrentHashMap<String, String>()
    private val genericPresenceTracker = GenericBlePresenceTracker()
    @Volatile
    private var lanBridge: LinkAdapter? = null

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
    private var adaptiveScanStartRunnable: Runnable? = null
    private var adaptiveScanStopRunnable: Runnable? = null
    private var recoveryScanStopRunnable: Runnable? = null
    private var handshakeCleanupRunnable: Runnable? = null
    private var scanWatchdogRunnable: Runnable? = null
    private var scanRetryRunnable: Runnable? = null
    private var keepAliveRunnable: Runnable? = null
    private var meshScanRunning = false
    private var meshScanStartedAt = 0L
    private var lastMeshScanResultAt = 0L
    private var scanRetryAttempt = 0
    private var scanErrorActive = false
    private var batteryLevel = 100
    private var charging = false
    private var screenOn = true
    private var systemPowerSave = false
    private var powerProfile = PowerProfile.BALANCED
    private var adaptivePowerSaving = false

    @Volatile
    private var notificationError: String? = null

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
    private data class PendingBeaconRequest(
        val peerId: String,
        val nickname: String,
        val control: BeaconControlProtocol.Control,
    )
    private data class OutgoingBeaconRequest(
        val peerId: String,
        val expiresAt: Long,
        val flags: Int,
    )
    private var activeBeaconRequest: PendingBeaconRequest? = null

    val peerId: String get() = identity.peerIdHex
    val nickname: String get() = identity.nickname

    fun stateSnapshot(): Map<String, Any?> = mapOf(
        "type" to "snapshot",
        "status" to currentStatus,
        "peerId" to peerId,
        "nickname" to nickname,
        "signingPublicKey" to identity.signingPublicKey,
        "role" to localRole.wireName,
        "batteryLevel" to batteryLevel,
        "adaptivePowerSaving" to adaptivePowerSaving,
        "powerProfile" to powerProfile.wireName,
        "radarConsentUntil" to activeLocalRadarConsentUntil(),
        "localBeaconActive" to beaconActuator.isActive(),
        "localBeaconExpiresAt" to beaconActuator.activeUntil(),
        "links" to activeLinks().map { it.capabilities.toEventMap() },
        "peers" to peersSnapshot(),
        "presences" to genericPresenceTracker.snapshot(System.currentTimeMillis())
            .map(GenericBlePresenceTracker.Presence::toEventMap),
    )

    fun notificationSnapshot(): MeshNotificationState = MeshNotificationState(
        status = currentStatus,
        nearbyPeerCount = nearbyPeerCount(),
        errorMessage = notificationError,
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
        scheduleHandshakeCleanup()
        scheduleScanWatchdog()
        scheduleKeepAlive()
        startAdvertising()
    }

    fun ensureStarted() {
        if (running) {
            rearmDataPlaneAfterClientAttach()
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

    /**
     * El proceso y la notificación pueden seguir marcando la malla como activa
     * aunque Android haya invalidado silenciosamente el escaneo. Cada nueva
     * solicitud de inicio desde Flutter rearma el plano de datos sin borrar
     * peers, sesiones Noise ni mensajes pendientes.
     */
    @SuppressLint("MissingPermission")
    private fun rearmDataPlaneAfterClientAttach() {
        scheduleHandshakeCleanup()
        scheduleScanWatchdog()
        rescheduleKeepAlive()
        if (localRole == MeshNodeRole.PHONE_BEACON) return
        if (gattServer == null) startGattServer()
        scanRetryRunnable?.let(mainHandler::removeCallbacks)
        scanRetryRunnable = null
        cancelRecoveryScanBurst()
        cancelAdaptiveScanning()
        stopBleScans()
        startScanning(aggressive = radarPeerId != null)
        startGenericBeaconScanning()
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

    /**
     * Frontera raw explícita para el cliente LAN autenticado de Flutter.
     * El adapter solo copia frames completos; [receive] conserva la autoridad
     * sobre validación, deduplicación y el único decremento de TTL.
     */
    fun configureLanBridge(enabled: Boolean, gatewayId: String?, maxFrameSize: Int) {
        if (!enabled) {
            lanBridge = null
            emit(stateSnapshot())
            return
        }
        val normalized = LanBridgePolicy.validateGatewayId(gatewayId)
        LanBridgePolicy.validateMaximumFrameSize(maxFrameSize)
        lanBridge = CallbackLinkAdapter(
            capabilities = LinkCapabilities(
                id = "lan:$normalized",
                kind = LinkKind.LAN,
                mtu = maxFrameSize,
                broadcast = true,
                unicast = true,
                reliability = LinkReliability.ACKNOWLEDGED,
                background = false,
                maxConnections = 1,
                cost = LAN_LINK_COST,
            ),
        ) { frame ->
            emit(
                mapOf(
                    "type" to "rawMeshFrame",
                    "gatewayId" to normalized,
                    "frame" to frame.copyOf(),
                ),
            )
            true
        }
        emit(stateSnapshot())
    }

    fun injectRawMeshFrame(gatewayId: String, frame: ByteArray) {
        val normalized = gatewayId.lowercase()
        val bridge = lanBridge
        require(bridge != null && bridge.capabilities.id == "lan:$normalized") {
            "El puente LAN no está habilitado para este gateway"
        }
        receive(LanBridgePolicy.validateFrame(frame, bridge.capabilities.mtu), normalized)
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
        beaconActuator.stop()
        pendingBeaconRequests.clear()
        outgoingBeaconRequests.clear()
        seenBeaconActions.clear()
        activeBeaconRequest = null
        addressToPeer.clear()
        runCatching { adapter.bluetoothLeScanner?.stopScan(scanCallback) }
        runCatching { adapter.bluetoothLeScanner?.stopScan(genericBeaconScanCallback) }
        genericPresenceEmitRunnable?.let(mainHandler::removeCallbacks)
        genericPresenceEmitRunnable = null
        cancelAdaptiveScanning()
        cancelRecoveryScanBurst()
        scanWatchdogRunnable?.let(mainHandler::removeCallbacks)
        scanWatchdogRunnable = null
        scanRetryRunnable?.let(mainHandler::removeCallbacks)
        scanRetryRunnable = null
        keepAliveRunnable?.let(mainHandler::removeCallbacks)
        keepAliveRunnable = null
        handshakeCleanupRunnable?.let(mainHandler::removeCallbacks)
        handshakeCleanupRunnable = null
        genericPresenceTracker.clear()
        clientGatts.values.forEach { runCatching { it.close() } }
        clientGatts.clear()
        knownDevices.clear()
        reconnectPeerByAddress.clear()
        autoReconnectExpiryByAddress.clear()
        autoReconnectAddresses.clear()
        autoReconnectScheduledAddresses.clear()
        overflowCandidateAddresses.clear()
        overflowCandidateCooldownUntil.clear()
        overflowMaskByAddress.clear()
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
        noiseFailureTracker.clear()
        lastHandshakeAttemptByPeer.clear()
        latestAnnouncementTimestampByPeer.clear()
        meshScanRunning = false
        meshScanStartedAt = 0L
        lastMeshScanResultAt = 0L
        scanRetryAttempt = 0
        scanErrorActive = false
        fragmentReassembler.clear()
        lastSyncRequestByAddress.clear()
        syncResponseTimes.clear()
        pendingCourier.clear()
        remoteRadarConsents.clear()
        tentativeRadarReads.clear()
        if (notify) emitStatus("stopped")
        lanBridge = null
    }

    fun updateNickname(value: String) {
        identity.nickname = value.trim().ifEmpty { "SOS-${peerId.takeLast(4)}" }
        sendAnnouncement()
    }

    fun updatePowerState(
        percent: Int,
        isCharging: Boolean,
        isScreenOn: Boolean,
        isSystemPowerSave: Boolean,
    ) {
        val normalized = percent.coerceIn(0, 100)
        batteryLevel = normalized
        charging = isCharging
        screenOn = isScreenOn
        systemPowerSave = isSystemPowerSave
        val nextProfile = AdaptivePowerPolicy.profileFor(
            batteryPercent = batteryLevel,
            isCharging = charging,
            screenOn = screenOn,
            systemPowerSave = systemPowerSave,
            survivalMode = localRole == MeshNodeRole.PHONE_BEACON,
        )
        val changed = nextProfile != powerProfile
        powerProfile = nextProfile
        adaptivePowerSaving = powerProfile.savesPower
        if (changed && running && localRole != MeshNodeRole.PHONE_BEACON && radarPeerId == null) {
            cancelAdaptiveScanning()
            cancelRecoveryScanBurst()
            stopBleScans()
            startScanning()
            startGenericBeaconScanning()
            restartAdvertising()
        }
        if (changed) rescheduleKeepAlive()
        emit(
            mapOf(
                "type" to "power",
                "batteryLevel" to batteryLevel,
                "adaptivePowerSaving" to adaptivePowerSaving,
                "powerProfile" to powerProfile.wireName,
            ),
        )
    }

    fun updateRole(value: String) {
        val nextRole = requireNotNull(MeshNodeRole.fromWireName(value)) {
            "Rol de nodo no válido"
        }
        if (nextRole == localRole) return
        val previousRole = localRole
        localRole = nextRole
        identity.nodeRole = localRole
        powerProfile = AdaptivePowerPolicy.profileFor(
            batteryPercent = batteryLevel,
            isCharging = charging,
            screenOn = screenOn,
            systemPowerSave = systemPowerSave,
            survivalMode = localRole == MeshNodeRole.PHONE_BEACON,
        )
        adaptivePowerSaving = powerProfile.savesPower
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
        rescheduleKeepAlive()
        emit(stateSnapshot())
    }

    @SuppressLint("MissingPermission")
    private fun enterPresenceOnlyMode() {
        if (!running || localRole != MeshNodeRole.PHONE_BEACON) return
        stopBleScans()
        genericPresenceEmitRunnable?.let(mainHandler::removeCallbacks)
        genericPresenceEmitRunnable = null
        genericPresenceTracker.clear()
        cancelRecoveryScanBurst()
        clientGatts.values.forEach { runCatching { it.close() } }
        clientGatts.clear()
        reconnectPeerByAddress.clear()
        autoReconnectExpiryByAddress.clear()
        autoReconnectAddresses.clear()
        autoReconnectScheduledAddresses.clear()
        overflowCandidateAddresses.clear()
        overflowMaskByAddress.clear()
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
        noiseFailureTracker.clear()
        lastHandshakeAttemptByPeer.clear()
        latestAnnouncementTimestampByPeer.clear()
        rescheduleKeepAlive()
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

    fun startLocalBeacon(
        flags: Int,
        durationMs: Long = BeaconControlProtocol.MAX_DURATION_MS,
    ) {
        val expiresAt = System.currentTimeMillis() +
            durationMs.coerceIn(1L, BeaconControlProtocol.MAX_DURATION_MS)
        check(startBeaconActuator(flags, expiresAt)) {
            "No hay hardware disponible para las señales solicitadas"
        }
    }

    fun stopLocalBeacon() {
        val activeRequest = activeBeaconRequest
        beaconActuator.stop()
        activeBeaconRequest = null
        if (activeRequest != null) {
            sendBeaconControl(
                activeRequest.peerId,
                BeaconControlProtocol.stop(activeRequest.control.nonce),
            )
        }
        emitLocalBeaconState("stopped")
    }

    fun requestRemoteBeacon(
        peerIdHex: String,
        flags: Int,
        durationMs: Long = BeaconControlProtocol.MAX_DURATION_MS,
    ): String {
        val normalized = peerIdHex.lowercase()
        require(peers.containsKey(normalized)) {
            context.getString(R.string.error_peer_unavailable)
        }
        require(flags != 0 && flags and BeaconControlProtocol.ALLOWED_FLAGS.inv() == 0)
        val expiresAt = System.currentTimeMillis() +
            durationMs.coerceIn(1L, BeaconControlProtocol.MAX_DURATION_MS)
        outgoingBeaconRequests.entries.removeIf {
            it.value.expiresAt <= System.currentTimeMillis()
        }
        val payload = BeaconControlProtocol.request(expiresAt, flags)
        val control = requireNotNull(BeaconControlProtocol.decode(payload))
        val requestId = BeaconControlProtocol.nonceHex(control.nonce)
        outgoingBeaconRequests[requestId] = OutgoingBeaconRequest(
            peerId = normalized,
            expiresAt = expiresAt,
            flags = flags,
        )
        sendBeaconControl(normalized, payload)
        emitRemoteBeaconState(normalized, requestId, "requested", expiresAt, flags)
        return requestId
    }

    fun respondToBeaconRequest(requestId: String, accept: Boolean) {
        val normalized = requestId.lowercase()
        val request = pendingBeaconRequests.remove(normalized)
            ?: throw IllegalArgumentException("La solicitud de baliza ya no está disponible")
        if (!BeaconControlProtocol.isValid(request.control, System.currentTimeMillis())) {
            sendBeaconControl(
                request.peerId,
                BeaconControlProtocol.revoke(request.control.nonce),
            )
            throw IllegalArgumentException("La solicitud de baliza expiró")
        }
        respondToBeaconRequest(request, accept, autoAccepted = false)
    }

    fun stopRemoteBeacon(peerIdHex: String, requestId: String) {
        val normalizedRequest = requestId.lowercase()
        val outgoing = outgoingBeaconRequests.remove(normalizedRequest)
            ?: throw IllegalArgumentException("La solicitud de baliza ya no está disponible")
        require(outgoing.peerId == peerIdHex.lowercase())
        sendBeaconControl(outgoing.peerId, BeaconControlProtocol.stop(normalizedRequest.hexToBytes()))
        emitRemoteBeaconState(
            outgoing.peerId,
            normalizedRequest,
            "stopped",
            0,
            0,
        )
    }

    fun sendPrivate(peerIdHex: String, content: String, messageId: String? = null): String {
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
        val id = messageId?.trim()?.takeIf { it.isNotEmpty() }?.take(255)
            ?: UUID.randomUUID().toString().uppercase()
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

    fun ensurePrivateChannel(peerIdHex: String) {
        check(localRole.canOriginateChat) {
            "El rol ${localRole.wireName} no puede originar chat"
        }
        val peer = peers[peerIdHex]
        require(peer != null && peer.role.canOriginateChat) {
            context.getString(R.string.error_peer_unavailable)
        }
        if (!noiseSessions.isEstablished(peerIdHex)) initiateHandshake(peerIdHex)
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
                "signingPublicKey" to it.signingPublicKey,
                "supportsTransfers" to it.supportsTransfers,
                "role" to it.role.wireName,
                "radarAllowedUntil" to (consent?.expiresAt ?: 0L),
                "radarConsentSource" to consent?.source,
            )
        }
    }

    fun panicWipe() {
        stop()
        beaconActuator.stop()
        pendingBeaconRequests.clear()
        outgoingBeaconRequests.clear()
        seenBeaconActions.clear()
        activeBeaconRequest = null
        storeForward.clear()
        relationshipPreferences.edit().clear().apply()
        peersWithSessionHistory.clear()
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
        cancelRecoveryScanBurst()
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
        broadcast(createAnnouncementPacket())
        broadcastHbtCapability()
        sendNodeCapability()
        if (activeLocalRadarConsentUntil() > System.currentTimeMillis()) {
            broadcastRadarConsent(grant = true)
        }
    }

    private fun createAnnouncementPacket(): MeshProtocol.Packet {
        val payload = MeshProtocol.encodeAnnouncement(
            nickname,
            identity.noisePublicKey,
            identity.signingPublicKey,
        )
        return identity.sign(
            MeshProtocol.Packet(
                type = MeshProtocol.TYPE_ANNOUNCE,
                ttl = MeshProtocol.TTL,
                timestamp = System.currentTimeMillis(),
                senderId = identity.peerId,
                payload = payload,
            ),
        )
    }

    private fun sendKeepAliveAnnouncement() {
        if (!running || !hasActiveBleLink()) return
        // El keepalive no entra al historial de REQUEST_SYNC: de lo contrario
        // anuncios frecuentes desplazarían mensajes útiles de la caché.
        broadcastBytes(MeshProtocol.encodeForBle(createAnnouncementPacket()), excludeAddress = null)
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

    private fun sendBeaconControl(peerIdHex: String, payload: ByteArray) {
        check(running) { "La malla no está activa" }
        val recipient = peerIdHex.hexToBytes()
        require(recipient.size == 8)
        broadcast(
            identity.sign(
                MeshProtocol.Packet(
                    type = MeshProtocol.TYPE_BEACON_CONTROL,
                    ttl = 1,
                    timestamp = System.currentTimeMillis(),
                    senderId = identity.peerId,
                    recipientId = recipient,
                    payload = payload,
                ),
            ),
        )
    }

    private fun respondToBeaconRequest(
        request: PendingBeaconRequest,
        accept: Boolean,
        autoAccepted: Boolean,
    ) {
        val requestId = BeaconControlProtocol.nonceHex(request.control.nonce)
        if (!accept || !startBeaconActuator(request.control.flags, request.control.expiresAt)) {
            sendBeaconControl(
                request.peerId,
                BeaconControlProtocol.revoke(request.control.nonce),
            )
            emit(
                mapOf(
                    "type" to "beaconRequestResolved",
                    "requestId" to requestId,
                    "peerId" to request.peerId,
                    "accepted" to false,
                    "autoAccepted" to autoAccepted,
                ),
            )
            return
        }
        activeBeaconRequest = request
        sendBeaconControl(
            request.peerId,
            BeaconControlProtocol.grant(
                request.control.expiresAt,
                request.control.flags,
                request.control.nonce,
            ),
        )
        emit(
            mapOf(
                "type" to "beaconRequestResolved",
                "requestId" to requestId,
                "peerId" to request.peerId,
                "accepted" to true,
                "autoAccepted" to autoAccepted,
            ),
        )
    }

    private fun startBeaconActuator(flags: Int, expiresAt: Long): Boolean {
        val started = beaconActuator.start(flags, expiresAt) {
            val expired = activeBeaconRequest
            activeBeaconRequest = null
            if (expired != null && running) {
                runCatching {
                    sendBeaconControl(
                        expired.peerId,
                        BeaconControlProtocol.stop(expired.control.nonce),
                    )
                }
            }
            emitLocalBeaconState("expired")
        }
        if (started) emitLocalBeaconState("active", flags, expiresAt)
        return started
    }

    private fun emitLocalBeaconState(
        status: String,
        flags: Int = 0,
        expiresAt: Long = 0,
    ) {
        emit(
            mapOf(
                "type" to "beaconState",
                "scope" to "local",
                "status" to status,
                "flags" to flags,
                "expiresAt" to expiresAt,
            ),
        )
    }

    private fun emitRemoteBeaconState(
        peerIdHex: String,
        requestId: String,
        status: String,
        expiresAt: Long,
        flags: Int,
    ) {
        emit(
            mapOf(
                "type" to "beaconState",
                "scope" to "remote",
                "peerId" to peerIdHex,
                "requestId" to requestId,
                "status" to status,
                "expiresAt" to expiresAt,
                "flags" to flags,
            ),
        )
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

    private fun initiateHandshake(peerIdHex: String, now: Long = System.currentTimeMillis()) {
        val previousAttempt = lastHandshakeAttemptByPeer[peerIdHex]
        if (previousAttempt != null && now - previousAttempt < HANDSHAKE_RETRY_THROTTLE_MS) return
        val peerBytes = peerIdHex.hexToBytes()
        val first = runCatching { noiseSessions.initiate(peerIdHex) }.getOrElse {
            emitError(context.getString(R.string.error_private_channel, it.message))
            return
        } ?: return
        lastHandshakeAttemptByPeer[peerIdHex] = now
        sendNoisePacket(MeshProtocol.TYPE_NOISE_HANDSHAKE, peerBytes, first)
    }

    private fun recoverNoiseSession(peerIdHex: String) {
        noiseSessions.invalidate(peerIdHex)
        lastHandshakeAttemptByPeer.remove(peerIdHex)
        initiateHandshake(peerIdHex)
    }

    private fun hasPendingRelationship(peerIdHex: String): Boolean =
        pendingPrivate[peerIdHex]?.isNotEmpty() == true ||
            pendingFrames[peerIdHex]?.isNotEmpty() == true ||
            pendingCourier[peerIdHex]?.isNotEmpty() == true

    private fun isKnownRelationship(peerIdHex: String): Boolean =
        peersWithSessionHistory.contains(peerIdHex) ||
            hasPendingRelationship(peerIdHex)

    @Synchronized
    private fun rememberSessionPeer(peerIdHex: String) {
        if (!peersWithSessionHistory.add(peerIdHex)) return
        val overflow = peersWithSessionHistory.size - MAX_REMEMBERED_SESSION_PEERS
        if (overflow > 0) {
            peersWithSessionHistory.asSequence()
                .filterNot { it == peerIdHex }
                .take(overflow)
                .toList()
                .forEach(peersWithSessionHistory::remove)
        }
        relationshipPreferences.edit()
            .putStringSet(
                KEY_SESSION_PEERS,
                peersWithSessionHistory.toSet(),
            )
            .apply()
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
            packet.type != MeshProtocol.TYPE_BEACON_CONTROL &&
            packet.recipientId != null &&
            !packet.recipientId.contentEquals(MeshProtocol.broadcastRecipient)
        ) {
            storeForward.put(packet)
        }
    }

    @SuppressLint("MissingPermission")
    private fun broadcastBytes(bytes: ByteArray, excludeAddress: String?) {
        activeLinks()
            .filterNot { it.capabilities.id.substringAfter(':') == excludeAddress }
            .forEach { sendViaLink(it, bytes) }
    }

    private fun activeLinks(): List<LinkAdapter> {
        val links = mutableListOf<LinkAdapter>()
        val characteristic = serverCharacteristic
        val server = gattServer
        if (characteristic != null && server != null) {
            serverSubscribers.forEach { device ->
                val maximumSize = serverMaximumGattValueSizes[device.address]
                    ?: DEFAULT_GATT_VALUE_SIZE
                links += CallbackLinkAdapter(
                    capabilities = bleCapabilities(
                        id = "ble-server:${device.address}",
                        mtu = maximumSize,
                        reliability = LinkReliability.BEST_EFFORT,
                    ),
                ) { frame ->
                    enqueueServerNotifications(
                        device,
                        server,
                        characteristic,
                        listOf(frame),
                    )
                    true
                }
            }
        }
        clientCharacteristics.forEach { (address, remoteCharacteristic) ->
            val gatt = clientGatts[address] ?: return@forEach
            val maximumSize = clientMaximumGattValueSizes[address] ?: DEFAULT_GATT_VALUE_SIZE
            links += CallbackLinkAdapter(
                capabilities = bleCapabilities(
                    id = "ble-client:$address",
                    mtu = maximumSize,
                    reliability = LinkReliability.ACKNOWLEDGED,
                ),
            ) { frame ->
                enqueueClientWrites(address, gatt, remoteCharacteristic, listOf(frame))
                true
            }
        }
        lanBridge?.let(links::add)
        return links
    }

    private fun bleCapabilities(
        id: String,
        mtu: Int,
        reliability: LinkReliability,
    ): LinkCapabilities = LinkCapabilities(
        id = id,
        kind = LinkKind.BLE,
        mtu = mtu,
        broadcast = false,
        unicast = true,
        reliability = reliability,
        background = true,
        maxConnections = MAX_BLE_CONNECTIONS,
        cost = BLE_LINK_COST,
    )

    private fun sendViaLink(link: LinkAdapter, bytes: ByteArray): Boolean {
        val frames = packetFragmenter.prepare(bytes, link.capabilities.mtu)
        if (frames == null) {
            Log.w(
                LOG_TAG,
                "Dropping ${bytes.size}-byte packet for ${link.capabilities.id} " +
                    "(limit=${link.capabilities.mtu})",
            )
            emitLinkTelemetry(link.capabilities, bytes.size, 0, accepted = false)
            return false
        }
        val accepted = frames.all(link::send)
        emitLinkTelemetry(link.capabilities, bytes.size, frames.size, accepted)
        return accepted
    }

    private fun emitLinkTelemetry(
        capabilities: LinkCapabilities,
        packetBytes: Int,
        frames: Int,
        accepted: Boolean,
    ) {
        emit(
            mapOf(
                "type" to "linkTelemetry",
                "link" to capabilities.toEventMap(),
                "packetBytes" to packetBytes,
                "frames" to frames,
                "accepted" to accepted,
            ),
        )
    }

    private fun LinkCapabilities.toEventMap(): Map<String, Any> = mapOf(
        "id" to id,
        "kind" to kind.name.lowercase(),
        "mtu" to mtu,
        "broadcast" to broadcast,
        "unicast" to unicast,
        "reliability" to reliability.name.lowercase(),
        "background" to background,
        "maxConnections" to maxConnections,
        "cost" to cost,
    )

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
        reconnectPeerByAddress.remove(address)?.let { peerId ->
            addressToPeer.putIfAbsent(address, peerId)
        }
        autoReconnectAddresses.remove(address)
        autoReconnectExpiryByAddress.remove(address)
        overflowCandidateAddresses.remove(address)
        notifyNotificationObserver()
        rescheduleKeepAlive()
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
        val fingerprint = MeshProtocol.relayFingerprint(bytes) ?: return
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
            MeshProtocol.TYPE_BEACON_CONTROL -> processBeaconControl(packet, senderHex)
            MeshProtocol.TYPE_FRAGMENT -> {
                val reassembled = fragmentReassembler.accept(packet)
                if (reassembled != null) {
                    if (reassembled.type == MeshProtocol.TYPE_BEACON_CONTROL &&
                        packet.ttl != 1.toByte()
                    ) {
                        return
                    }
                    Log.i(
                        LOG_TAG,
                        "FRAGMENT reassembled: type=${reassembled.type.toUByte()} " +
                            "sender=${senderHex.take(8)} bytes=${reassembled.payload.size}",
                    )
                    process(
                        if (reassembled.type == MeshProtocol.TYPE_BEACON_CONTROL) {
                            reassembled.copy(ttl = 1)
                        } else {
                            reassembled
                        },
                        senderHex,
                        sourceAddress,
                    )
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
        latestAnnouncementTimestampByPeer.merge(senderHex, packet.timestamp) { current, candidate ->
            maxOf(current, candidate)
        }
        rememberSyncPacket(packet)
        emit(mapOf("type" to "peers", "peers" to peersSnapshot()))
        notifyNotificationObserver()
        requestMissingMessages(senderHex, sourceAddress)
        storeForward.forRecipient(packet.senderId).forEach(::broadcast)
        if (isKnownRelationship(senderHex) && !noiseSessions.isEstablished(senderHex)) {
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

    private fun processBeaconControl(packet: MeshProtocol.Packet, senderHex: String) {
        if (packet.ttl != 1.toByte() ||
            packet.recipientId?.contentEquals(identity.peerId) != true
        ) {
            return
        }
        val peer = peers[senderHex] ?: return
        if (!identity.verify(packet, peer.signingPublicKey)) return
        val control = BeaconControlProtocol.decode(packet.payload) ?: return
        if (!BeaconControlProtocol.isValid(control, packet.timestamp)) return
        val requestId = BeaconControlProtocol.nonceHex(control.nonce)
        val now = System.currentTimeMillis()
        seenBeaconActions.entries.removeIf { it.value <= now }
        val replayKey = "$senderHex:$requestId:${control.action}"
        if (seenBeaconActions.putIfAbsent(replayKey, now + BEACON_REPLAY_WINDOW_MS) != null) {
            return
        }
        when (control.action) {
            BeaconControlProtocol.ACTION_REQUEST -> {
                if (activeBeaconRequest != null) {
                    sendBeaconControl(
                        senderHex,
                        BeaconControlProtocol.revoke(control.nonce),
                    )
                    return
                }
                pendingBeaconRequests.entries.removeIf {
                    it.value.control.expiresAt <= now
                }
                if (pendingBeaconRequests.size >= MAX_PENDING_BEACON_REQUESTS) {
                    sendBeaconControl(
                        senderHex,
                        BeaconControlProtocol.revoke(control.nonce),
                    )
                    return
                }
                val request = PendingBeaconRequest(senderHex, peer.nickname, control)
                pendingBeaconRequests[requestId] = request
                if (BeaconControlProtocol.shouldAutoAccept(activeLocalRadarConsentUntil())) {
                    pendingBeaconRequests.remove(requestId)
                    emit(
                        mapOf(
                            "type" to "beaconRequest",
                            "requestId" to requestId,
                            "peerId" to senderHex,
                            "nickname" to peer.nickname,
                            "expiresAt" to control.expiresAt,
                            "flags" to control.flags,
                            "autoAccepted" to true,
                        ),
                    )
                    respondToBeaconRequest(request, accept = true, autoAccepted = true)
                } else {
                    emit(
                        mapOf(
                            "type" to "beaconRequest",
                            "requestId" to requestId,
                            "peerId" to senderHex,
                            "nickname" to peer.nickname,
                            "expiresAt" to control.expiresAt,
                            "flags" to control.flags,
                            "autoAccepted" to false,
                        ),
                    )
                }
            }
            BeaconControlProtocol.ACTION_GRANT -> {
                val outgoing = outgoingBeaconRequests[requestId] ?: return
                if (outgoing.peerId != senderHex ||
                    outgoing.flags != control.flags ||
                    control.expiresAt > outgoing.expiresAt
                ) {
                    return
                }
                emitRemoteBeaconState(
                    senderHex,
                    requestId,
                    "active",
                    control.expiresAt,
                    control.flags,
                )
            }
            BeaconControlProtocol.ACTION_REVOKE -> {
                val outgoing = outgoingBeaconRequests.remove(requestId) ?: return
                if (outgoing.peerId != senderHex) return
                emitRemoteBeaconState(senderHex, requestId, "rejected", 0, 0)
            }
            BeaconControlProtocol.ACTION_STOP -> {
                val active = activeBeaconRequest
                if (active?.peerId == senderHex &&
                    active.control.nonce.contentEquals(control.nonce)
                ) {
                    beaconActuator.stop()
                    activeBeaconRequest = null
                    emitLocalBeaconState("stopped")
                }
                val outgoing = outgoingBeaconRequests.remove(requestId)
                if (outgoing?.peerId == senderHex) {
                    emitRemoteBeaconState(senderHex, requestId, "stopped", 0, 0)
                }
            }
        }
    }

    private fun processHandshake(packet: MeshProtocol.Packet, senderHex: String) {
        if (!NoiseReplayPolicy.isCurrent(
                packet.timestamp,
                latestAnnouncementTimestampByPeer[senderHex],
            )
        ) {
            Log.i(LOG_TAG, "Ignoring stale Noise handshake from ${senderHex.take(8)}")
            return
        }
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
            Log.i(LOG_TAG, "Noise session established with ${senderHex.take(8)}")
            rememberSessionPeer(senderHex)
            noiseFailureTracker.recordSuccess(senderHex)
            lastHandshakeAttemptByPeer.remove(senderHex)
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
        if (!NoiseReplayPolicy.isCurrent(
                packet.timestamp,
                latestAnnouncementTimestampByPeer[senderHex],
            )
        ) {
            Log.i(LOG_TAG, "Ignoring stale Noise ciphertext from ${senderHex.take(8)}")
            return
        }
        val hadEstablishedSession = noiseSessions.isEstablished(senderHex)
        if (!hadEstablishedSession) {
            noiseSessions.cleanupStaleHandshakes()
            if (!noiseSessions.hasSession(senderHex) &&
                noiseFailureTracker.recordFailure(
                    senderHex,
                    hadEstablishedSession = false,
                ) == NoiseRecoveryAction.RENEGOTIATE
            ) {
                initiateHandshake(senderHex)
            }
            return
        }
        val plaintext = runCatching { noiseSessions.decrypt(senderHex, packet.payload) }
            .getOrElse {
                if (noiseFailureTracker.recordFailure(
                        senderHex,
                        hadEstablishedSession = true,
                    ) == NoiseRecoveryAction.RENEGOTIATE
                ) {
                    recoverNoiseSession(senderHex)
                }
                return
            }
        noiseFailureTracker.recordSuccess(senderHex)
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
        Log.i(LOG_TAG, "Private message decrypted from ${senderHex.take(8)}")
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
        val fingerprint = MeshProtocol.relayFingerprint(envelope.ciphertext) ?: return
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
        activeLinks()
            .filter { it.capabilities.id.substringAfter(':') == address }
            .forEach { sendViaLink(it, bytes) }
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
            .setAdvertiseMode(powerProfile.advertiseMode)
            .setTxPowerLevel(powerProfile.advertiseTxPower)
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
        if (powerProfile.scanMode == null && !aggressive) return
        if (powerProfile.usesDutyCycle && !aggressive) {
            scheduleAdaptiveScanning()
            return
        }
        if (aggressive) cancelAdaptiveScanning()
        startMeshScan(
            scanMode = if (aggressive) {
                ScanSettings.SCAN_MODE_LOW_LATENCY
            } else {
                powerProfile.scanMode ?: return
            },
            aggressive = aggressive,
        )
    }

    @SuppressLint("MissingPermission")
    private fun startMeshScan(scanMode: Int, aggressive: Boolean) {
        val now = System.currentTimeMillis()
        val sinceLastStart = now - meshScanStartedAt
        if (meshScanStartedAt > 0L &&
            sinceLastStart < MeshScanHealthPolicy.MINIMUM_SCAN_START_INTERVAL_MS
        ) {
            val delay =
                MeshScanHealthPolicy.MINIMUM_SCAN_START_INTERVAL_MS - sinceLastStart
            scanRetryRunnable?.let(mainHandler::removeCallbacks)
            scanRetryRunnable = Runnable {
                scanRetryRunnable = null
                if (running) startMeshScan(scanMode, aggressive)
            }.also { mainHandler.postDelayed(it, delay) }
            return
        }
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build()
        val settingsBuilder = ScanSettings.Builder()
            .setScanMode(scanMode)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
        if (aggressive) {
            settingsBuilder
                .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
                .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
        }
        val settings = settingsBuilder.build()
        val scanner = adapter.bluetoothLeScanner ?: run {
            meshScanRunning = false
            scheduleScanRetry()
            return
        }
        runCatching { scanner.stopScan(scanCallback) }
        meshScanRunning = false
        runCatching {
            scanner.startScan(listOf(filter), settings, scanCallback)
        }.onSuccess {
            meshScanRunning = true
            meshScanStartedAt = now
        }.onFailure {
            Log.w(LOG_TAG, "Unable to start mesh scan", it)
            scheduleScanRetry()
        }
    }

    /**
     * Segundo nivel: presencia BLE genérica. Se escanea sin filtro, pero no se
     * conecta al dispositivo ni se leen nombre o MAC. Solo se publican IDs
     * locales rotativos producidos por [GenericBlePresenceTracker].
     */
    @SuppressLint("MissingPermission")
    private fun startGenericBeaconScanning() {
        if (powerProfile.scanMode == null) return
        if (powerProfile.usesDutyCycle) {
            scheduleAdaptiveScanning()
            return
        }
        startGenericBeaconScanNow()
    }

    @SuppressLint("MissingPermission")
    private fun startGenericBeaconScanNow() {
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
    private fun scheduleAdaptiveScanning() {
        if (
            !running ||
            !powerProfile.usesDutyCycle ||
            localRole == MeshNodeRole.PHONE_BEACON ||
            radarPeerId != null ||
            adaptiveScanStartRunnable != null ||
            adaptiveScanStopRunnable != null
        ) {
            return
        }
        val start = Runnable {
            adaptiveScanStartRunnable = null
            if (
                !running ||
                !powerProfile.usesDutyCycle ||
                localRole == MeshNodeRole.PHONE_BEACON ||
                radarPeerId != null
            ) {
                return@Runnable
            }
            startMeshScan(powerProfile.scanMode ?: return@Runnable, aggressive = false)
            startGenericBeaconScanNow()
            adaptiveScanStopRunnable = Runnable {
                adaptiveScanStopRunnable = null
                if (!running || radarPeerId != null) return@Runnable
                stopMeshScan()
                runCatching { adapter.bluetoothLeScanner?.stopScan(genericBeaconScanCallback) }
                adaptiveScanStartRunnable = Runnable {
                    adaptiveScanStartRunnable = null
                    scheduleAdaptiveScanning()
                }.also {
                    mainHandler.postDelayed(it, powerProfile.scanPauseMs)
                }
            }.also {
                mainHandler.postDelayed(it, powerProfile.scanBurstMs)
            }
        }
        adaptiveScanStartRunnable = start
        mainHandler.post(start)
    }

    private fun cancelAdaptiveScanning() {
        adaptiveScanStartRunnable?.let(mainHandler::removeCallbacks)
        adaptiveScanStopRunnable?.let(mainHandler::removeCallbacks)
        adaptiveScanStartRunnable = null
        adaptiveScanStopRunnable = null
    }

    @SuppressLint("MissingPermission")
    private fun triggerRecoveryScanBurst() {
        if (!running ||
            localRole == MeshNodeRole.PHONE_BEACON ||
            powerProfile.scanMode == null ||
            radarPeerId != null
        ) {
            return
        }
        recoveryScanStopRunnable?.let(mainHandler::removeCallbacks)
        cancelAdaptiveScanning()
        startMeshScan(ScanSettings.SCAN_MODE_LOW_LATENCY, aggressive = true)
        recoveryScanStopRunnable = Runnable {
            recoveryScanStopRunnable = null
            if (!running || radarPeerId != null || localRole == MeshNodeRole.PHONE_BEACON) {
                return@Runnable
            }
            stopMeshScan()
            startScanning()
        }.also { mainHandler.postDelayed(it, RECOVERY_SCAN_BURST_MS) }
    }

    private fun cancelRecoveryScanBurst() {
        recoveryScanStopRunnable?.let(mainHandler::removeCallbacks)
        recoveryScanStopRunnable = null
    }

    private fun scheduleHandshakeCleanup() {
        if (!running || handshakeCleanupRunnable != null) return
        handshakeCleanupRunnable = Runnable {
            handshakeCleanupRunnable = null
            if (!running) return@Runnable
            noiseSessions.cleanupStaleHandshakes().forEach { peerId ->
                if (isKnownRelationship(peerId) && peers.containsKey(peerId)) {
                    initiateHandshake(peerId)
                }
            }
            scheduleHandshakeCleanup()
        }.also { mainHandler.postDelayed(it, HANDSHAKE_CLEANUP_INTERVAL_MS) }
    }

    private fun hasActiveBleLink(): Boolean =
        clientReady.isNotEmpty() || serverSubscribers.isNotEmpty()

    private fun scheduleKeepAlive() {
        if (!running || keepAliveRunnable != null) return
        val interval = MeshKeepAlivePolicy.intervalMs(powerProfile, hasActiveBleLink()) ?: return
        keepAliveRunnable = Runnable {
            keepAliveRunnable = null
            if (!running) return@Runnable
            sendKeepAliveAnnouncement()
            scheduleKeepAlive()
        }.also { mainHandler.postDelayed(it, interval) }
    }

    private fun rescheduleKeepAlive() {
        keepAliveRunnable?.let(mainHandler::removeCallbacks)
        keepAliveRunnable = null
        scheduleKeepAlive()
    }

    private fun hasReachedConnectionLimit(knownPeer: Boolean): Boolean {
        return !ConnectionPriorityPolicy.canOpenClientConnection(
            maximumConnections = powerProfile.maximumClientConnections,
            activeConnections = clientGatts.size,
            knownPeer = knownPeer,
        )
    }

    @SuppressLint("MissingPermission")
    private fun stopBleScans() {
        stopMeshScan()
        runCatching { adapter.bluetoothLeScanner?.stopScan(genericBeaconScanCallback) }
    }

    @SuppressLint("MissingPermission")
    private fun stopMeshScan() {
        runCatching { adapter.bluetoothLeScanner?.stopScan(scanCallback) }
        meshScanRunning = false
    }

    private fun shouldScanContinuously(): Boolean =
        running &&
            localRole != MeshNodeRole.PHONE_BEACON &&
            powerProfile.scanMode != null &&
            (!powerProfile.usesDutyCycle || radarPeerId != null || recoveryScanStopRunnable != null)

    private fun scheduleScanWatchdog() {
        if (!running || scanWatchdogRunnable != null) return
        scanWatchdogRunnable = Runnable {
            scanWatchdogRunnable = null
            if (!running) return@Runnable
            val now = System.currentTimeMillis()
            val action = MeshScanHealthPolicy.actionFor(
                shouldScanContinuously = shouldScanContinuously(),
                isScanning = meshScanRunning,
                now = now,
                scanStartedAt = meshScanStartedAt,
                lastResultAt = lastMeshScanResultAt,
                expectsKnownPeer = autoReconnectExpiryByAddress.values.any { it > now },
            )
            when (action) {
                MeshScanHealthAction.NONE -> Unit
                MeshScanHealthAction.START -> startScanning(radarPeerId != null)
                MeshScanHealthAction.RESTART -> forceRestartContinuousScans()
            }
            scheduleScanWatchdog()
        }.also {
            mainHandler.postDelayed(it, MeshScanHealthPolicy.WATCHDOG_INTERVAL_MS)
        }
    }

    @SuppressLint("MissingPermission")
    private fun forceRestartContinuousScans() {
        if (!shouldScanContinuously()) return
        Log.i(LOG_TAG, "Re-arming continuous BLE scans")
        stopBleScans()
        scanRetryRunnable?.let(mainHandler::removeCallbacks)
        scanRetryRunnable = Runnable {
            scanRetryRunnable = null
            if (!shouldScanContinuously()) return@Runnable
            startScanning(radarPeerId != null)
            startGenericBeaconScanning()
        }.also { mainHandler.postDelayed(it, SCAN_REARM_DELAY_MS) }
    }

    private fun scheduleScanRetry() {
        meshScanRunning = false
        if (!running || powerProfile.scanMode == null || scanRetryRunnable != null) return
        scanRetryAttempt = (scanRetryAttempt + 1).coerceAtMost(MAX_SCAN_RETRY_ATTEMPTS)
        val delay = MeshScanHealthPolicy.retryDelayMs(
            attempt = scanRetryAttempt,
            now = System.currentTimeMillis(),
            lastScanStartAt = meshScanStartedAt,
        )
        scanRetryRunnable = Runnable {
            scanRetryRunnable = null
            if (!running || powerProfile.scanMode == null) return@Runnable
            startScanning(radarPeerId != null)
            startGenericBeaconScanning()
        }.also { mainHandler.postDelayed(it, delay) }
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
            lastMeshScanResultAt = System.currentTimeMillis()
            scanRetryAttempt = 0
            if (scanErrorActive) {
                scanErrorActive = false
                notificationError = null
                if (advertising) emitStatus("active") else notifyNotificationObserver()
            }
            runCatching { handleMeshScanResult(result) }
                .onFailure { Log.w(LOG_TAG, "Ignoring malformed mesh scan result", it) }
        }

        override fun onScanFailed(errorCode: Int) {
            meshScanRunning = false
            scanErrorActive = true
            emitError(context.getString(R.string.error_scan_failed, errorCode))
            scheduleScanRetry()
        }
    }

    private val genericBeaconScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            runCatching { handleGenericBeaconScanResult(result) }
                .onFailure { Log.w(LOG_TAG, "Ignoring malformed generic BLE result", it) }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.w(LOG_TAG, "Generic BLE presence scan failed: $errorCode")
            scheduleScanRetry()
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
        knownDevices[address] = result.device
        val advertisedPeerId = advertisedPeer?.let(MeshProtocol::hex)
        if (advertisedPeer != null) {
            addressToPeer[address] = checkNotNull(advertisedPeerId)
        }
        val radarTarget = radarPeerId
        if (radarTarget != null && addressToPeer[address] == radarTarget) {
            emitRssi(radarTarget, result.rssi)
        }
        if (clientGatts.containsKey(address)) return
        val knownPeer = advertisedPeerId?.let { peerId ->
            peers.containsKey(peerId) || isKnownRelationship(peerId)
        } == true
        connectToDevice(result.device, autoConnect = false, knownPeer = knownPeer)
    }

    @SuppressLint("MissingPermission")
    private fun handleGenericBeaconScanResult(result: ScanResult) {
        val record = result.scanRecord ?: return
        if (isMeshAdvertisement(record)) return
        val overflowMask = OverflowAreaMatcher.extractMask(
            record.getManufacturerSpecificData(OverflowAreaMatcher.APPLE_MANUFACTURER_ID),
        )
        if (overflowMask != null) handleIosOverflowCandidate(result, overflowMask)
        val changed = genericPresenceTracker.record(
            advertisementMaterial = genericAdvertisementMaterial(record),
            rssi = result.rssi,
            now = System.currentTimeMillis(),
        )
        if (changed) scheduleGenericPresenceEmit()
    }

    @SuppressLint("MissingPermission")
    private fun handleIosOverflowCandidate(result: ScanResult, mask: ByteArray) {
        if (!OverflowAreaMatcher.hasAnyService(mask) ||
            result.rssi < MIN_OVERFLOW_CANDIDATE_RSSI ||
            !hasDisconnectedKnownPeer()
        ) {
            return
        }
        val learnedBit = learnedIosOverflowBit
        if (learnedBit != null && !OverflowAreaMatcher.matchesBit(mask, learnedBit)) return

        val address = result.device.address
        val now = System.currentTimeMillis()
        overflowCandidateCooldownUntil.entries.removeIf { it.value <= now }
        if ((overflowCandidateCooldownUntil[address] ?: 0L) > now ||
            clientGatts.containsKey(address) ||
            overflowCandidateAddresses.size >= MAX_OVERFLOW_CANDIDATES
        ) {
            return
        }

        knownDevices[address] = result.device
        overflowMaskByAddress[address] = mask.copyOf()
        Log.i(
            LOG_TAG,
            "iOS overflow candidate ${address.takeLast(5)} mask=${OverflowAreaMatcher.toHex(mask)}",
        )
        val connected = connectToDevice(
            device = result.device,
            autoConnect = false,
            knownPeer = true,
            overflowCandidate = true,
        )
        if (!connected) overflowMaskByAddress.remove(address)
    }

    private fun hasDisconnectedKnownPeer(): Boolean {
        val knownPeerIds = peersWithSessionHistory.toSet() + peers.keys
        if (knownPeerIds.isEmpty()) return false
        val activeAddresses = clientReady.toSet() + serverSubscribers.map { it.address }
        val activePeerIds = activeAddresses.mapNotNull(addressToPeer::get).toSet()
        return knownPeerIds.any { it !in activePeerIds }
    }

    @SuppressLint("MissingPermission")
    private fun connectToDevice(
        device: BluetoothDevice,
        autoConnect: Boolean,
        knownPeer: Boolean,
        overflowCandidate: Boolean = false,
    ): Boolean {
        val address = device.address
        if (clientGatts.containsKey(address) || hasReachedConnectionLimit(knownPeer)) return false
        val gatt = runCatching {
            device.connectGatt(
                context,
                autoConnect,
                clientCallback,
                BluetoothDevice.TRANSPORT_LE,
            )
        }.onFailure {
            Log.w(LOG_TAG, "Unable to connect to ${address.takeLast(5)}", it)
        }.getOrNull() ?: return false
        val existing = clientGatts.putIfAbsent(address, gatt)
        if (existing != null) {
            runCatching { gatt.close() }
            return false
        }
        knownDevices[address] = device
        if (autoConnect) autoReconnectAddresses.add(address)
        if (overflowCandidate) overflowCandidateAddresses.add(address)
        return true
    }

    private fun acceptOverflowCandidate(address: String) {
        if (!overflowCandidateAddresses.remove(address)) return
        overflowCandidateCooldownUntil.remove(address)
        val mask = overflowMaskByAddress.remove(address) ?: return
        if (learnedIosOverflowBit != null) return
        val learnedBit = OverflowAreaMatcher.singleSetBit(mask) ?: return
        learnedIosOverflowBit = learnedBit
        relationshipPreferences.edit().putInt(KEY_IOS_OVERFLOW_BIT, learnedBit).apply()
        Log.i(LOG_TAG, "Learned iOS overflow service bit $learnedBit")
    }

    @SuppressLint("MissingPermission")
    private fun rejectClientConnection(gatt: BluetoothGatt) {
        val address = gatt.device.address
        val wasOverflowCandidate = overflowCandidateAddresses.remove(address)
        overflowMaskByAddress.remove(address)
        if (wasOverflowCandidate) {
            overflowCandidateCooldownUntil[address] =
                System.currentTimeMillis() + OVERFLOW_CANDIDATE_COOLDOWN_MS
        }
        autoReconnectAddresses.remove(address)
        clientGatts.remove(address, gatt)
        clientCharacteristics.remove(address)
        clientMaximumGattValueSizes.remove(address)
        clientReady.remove(address)
        runCatching { gatt.disconnect() }
        runCatching { gatt.close() }
        handleDirectLinkLost(address)
        rescheduleKeepAlive()
    }

    private fun handleDirectLinkLost(address: String) {
        val hasClientLink = clientReady.contains(address)
        val hasServerLink = serverSubscribers.any { it.address == address }
        if (hasClientLink || hasServerLink) return
        val disconnectedPeer =
            addressToPeer.remove(address) ?: reconnectPeerByAddress[address] ?: return
        reconnectPeerByAddress[address] = disconnectedPeer
        if (addressToPeer.values.none { it == disconnectedPeer }) {
            if (noiseSessions.isEstablished(disconnectedPeer)) {
                rememberSessionPeer(disconnectedPeer)
            }
            noiseSessions.invalidate(disconnectedPeer)
            noiseFailureTracker.clear(disconnectedPeer)
            lastHandshakeAttemptByPeer.remove(disconnectedPeer)
            emit(mapOf("type" to "peers", "peers" to peersSnapshot()))
            notifyNotificationObserver()
            triggerRecoveryScanBurst()
            scheduleKnownPeerAutoReconnect(address, disconnectedPeer)
        }
        rescheduleKeepAlive()
    }

    private fun scheduleKnownPeerAutoReconnect(address: String, peerId: String) {
        if (!running || localRole == MeshNodeRole.PHONE_BEACON) return
        val device = knownDevices[address] ?: return
        val now = System.currentTimeMillis()
        val expiry = autoReconnectExpiryByAddress.compute(address) { _, existing ->
            existing?.takeIf { it > now } ?: now + AUTO_RECONNECT_WINDOW_MS
        } ?: return
        if (expiry <= now ||
            clientGatts.containsKey(address) ||
            autoReconnectAddresses.size >= MAX_AUTO_RECONNECTS ||
            !autoReconnectScheduledAddresses.add(address)
        ) {
            return
        }

        reconnectPeerByAddress[address] = peerId
        mainHandler.postDelayed({
            autoReconnectScheduledAddresses.remove(address)
            val currentExpiry = autoReconnectExpiryByAddress[address] ?: return@postDelayed
            if (!running || currentExpiry <= System.currentTimeMillis() ||
                clientGatts.containsKey(address)
            ) {
                return@postDelayed
            }
            val connected = connectToDevice(
                device = device,
                autoConnect = true,
                knownPeer = true,
            )
            if (!connected) return@postDelayed
            val pendingGatt = clientGatts[address] ?: return@postDelayed
            mainHandler.postDelayed({
                if (autoReconnectExpiryByAddress[address] != currentExpiry ||
                    clientGatts[address] !== pendingGatt ||
                    clientReady.contains(address)
                ) {
                    return@postDelayed
                }
                clientGatts.remove(address, pendingGatt)
                autoReconnectAddresses.remove(address)
                autoReconnectExpiryByAddress.remove(address, currentExpiry)
                runCatching { pendingGatt.close() }
            }, (currentExpiry - System.currentTimeMillis()).coerceAtLeast(1L))
        }, AUTO_RECONNECT_DELAY_MS)
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
                knownDevices[gatt.device.address] = gatt.device
                clientMaximumGattValueSizes.putIfAbsent(
                    gatt.device.address,
                    DEFAULT_GATT_VALUE_SIZE,
                )
                if (!gatt.requestMtu(MeshPacketFragmenter.MAX_ATT_MTU)) gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                val wasOverflowCandidate = overflowCandidateAddresses.remove(gatt.device.address)
                overflowMaskByAddress.remove(gatt.device.address)
                if (wasOverflowCandidate) {
                    overflowCandidateCooldownUntil[gatt.device.address] =
                        System.currentTimeMillis() + OVERFLOW_CANDIDATE_COOLDOWN_MS
                }
                autoReconnectAddresses.remove(gatt.device.address)
                clientCharacteristics.remove(gatt.device.address)
                clientGatts.remove(gatt.device.address, gatt)
                clientMaximumGattValueSizes.remove(gatt.device.address)
                clientReady.remove(gatt.device.address)
                lastSyncRequestByAddress.remove(gatt.device.address)
                syncResponseTimes.remove(gatt.device.address)
                synchronized(clientWriteLock) {
                    clientWriteQueues.remove(gatt.device.address)
                    clientWritesInFlight.remove(gatt.device.address)
                }
                handleDirectLinkLost(gatt.device.address)
                rescheduleKeepAlive()
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
            if (status != BluetoothGatt.GATT_SUCCESS) {
                rejectClientConnection(gatt)
                return
            }
            val characteristic = gatt.getService(SERVICE_UUID)
                ?.getCharacteristic(CHARACTERISTIC_UUID)
            if (characteristic == null) {
                rejectClientConnection(gatt)
                return
            }
            acceptOverflowCandidate(gatt.device.address)
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
                knownDevices[device.address] = device
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
                rescheduleKeepAlive()
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
                notifyNotificationObserver()
                rescheduleKeepAlive()
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
        if (status == "starting" || status == "active" || status == "stopped") {
            notificationError = null
        }
        emit(
            mapOf(
                "type" to "status",
                "status" to status,
                "peerId" to peerId,
                "nickname" to nickname,
                "signingPublicKey" to identity.signingPublicKey,
                "role" to localRole.wireName,
            ),
        )
        notifyNotificationObserver()
    }

    private fun emitError(message: String) {
        notificationError = message
        emit(mapOf("type" to "error", "message" to message))
        notifyNotificationObserver()
    }

    private fun nearbyPeerCount(): Int {
        val knownPeers = peers.keys
        val activeAddresses = clientReady.toSet() + serverSubscribers.map { it.address }
        return activeAddresses.asSequence()
            .mapNotNull(addressToPeer::get)
            .filter(knownPeers::contains)
            .toSet()
            .size
    }

    private fun notifyNotificationObserver() {
        observeNotification(notificationSnapshot())
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
        const val BEACON_REPLAY_WINDOW_MS = 10 * 60_000L
        const val MAX_PENDING_BEACON_REQUESTS = 1

        const val ADVERTISE_TIMEOUT_MS = 10_000L
        const val MAX_ADVERTISE_RETRIES = 1
        const val MAX_PENDING_GATT_WRITES = 256
        const val MAX_BLE_CONNECTIONS = 8
        const val BLE_LINK_COST = 10
        const val LAN_LINK_COST = 2
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
        const val HANDSHAKE_RETRY_THROTTLE_MS = 5_000L
        const val HANDSHAKE_CLEANUP_INTERVAL_MS = 10_000L
        const val RECOVERY_SCAN_BURST_MS = 15_000L
        const val SCAN_REARM_DELAY_MS = 750L
        const val MAX_SCAN_RETRY_ATTEMPTS = 5
        const val AUTO_RECONNECT_DELAY_MS = 750L
        const val AUTO_RECONNECT_WINDOW_MS = 12 * 60_000L
        const val MAX_AUTO_RECONNECTS = 3
        const val MAX_OVERFLOW_CANDIDATES = 1
        const val OVERFLOW_CANDIDATE_COOLDOWN_MS = 5 * 60_000L
        const val MIN_OVERFLOW_CANDIDATE_RSSI = -90
        const val MAX_REMEMBERED_SESSION_PEERS = 256
        const val RELATIONSHIP_PREFERENCES = "hearthbit_mesh_relationships"
        const val KEY_SESSION_PEERS = "session_peers"
        const val KEY_IOS_OVERFLOW_BIT = "ios_overflow_service_bit"

        const val LOG_TAG = "HearthBitMesh"

        val SERVICE_UUID: UUID =
            UUID.fromString("F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C")
        val CHARACTERISTIC_UUID: UUID =
            UUID.fromString("A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D")
        val CLIENT_CONFIGURATION_UUID: UUID =
            UUID.fromString("00002902-0000-1000-8000-00805F9B34FB")
    }
}
