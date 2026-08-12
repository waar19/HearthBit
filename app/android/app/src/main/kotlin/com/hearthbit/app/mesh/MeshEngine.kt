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
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import java.util.Collections
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

internal class MeshEngine(
    private val context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val bluetoothManager = context.getSystemService(BluetoothManager::class.java)
    private val adapter get() = bluetoothManager.adapter
    private val identity = MeshIdentity(context)
    private val seen = Collections.synchronizedMap(
        object : LinkedHashMap<String, Long>(512, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Long>?): Boolean =
                size > 2_000
        },
    )
    private val peers = ConcurrentHashMap<String, Peer>()
    private val sessions = ConcurrentHashMap<String, NoiseSessionLite>()
    private val pendingPrivate = ConcurrentHashMap<String, MutableList<PendingPrivate>>()
    private val pendingFrames = ConcurrentHashMap<String, MutableList<ByteArray>>()
    private val clientGatts = ConcurrentHashMap<String, BluetoothGatt>()
    private val clientCharacteristics =
        ConcurrentHashMap<String, BluetoothGattCharacteristic>()
    private val serverSubscribers = ConcurrentHashMap.newKeySet<BluetoothDevice>()
    private val storeForward = StoreForwardCache(context)

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

    /** Peer objetivo del radar de rescate; null cuando el radar está apagado. */
    @Volatile
    private var radarPeerId: String? = null

    data class Peer(
        val id: String,
        val nickname: String,
        val signingPublicKey: ByteArray,
        var lastSeen: Long = System.currentTimeMillis(),
    )

    private data class PendingPrivate(val id: String, val content: String)

    val peerId: String get() = identity.peerIdHex
    val nickname: String get() = identity.nickname

    @SuppressLint("MissingPermission")
    fun start() {
        check(adapter != null && adapter.isEnabled) { "Bluetooth está apagado" }
        // Reinicio real: si ya estaba corriendo (por ejemplo tras un fallo de
        // advertising) se liberan los recursos antes de volver a intentarlo.
        if (running) stopInternal(notify = false)
        running = true
        emitStatus("starting")
        startGattServer()
        startScanning()
        startAdvertising()
    }

    fun stop() {
        if (!running) return
        stopInternal(notify = true)
    }

    @SuppressLint("MissingPermission")
    private fun stopInternal(notify: Boolean) {
        running = false
        advertising = false
        stopRadar()
        addressToPeer.clear()
        runCatching { adapter.bluetoothLeScanner?.stopScan(scanCallback) }
        runCatching { adapter.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback) }
        clientGatts.values.forEach { runCatching { it.close() } }
        clientGatts.clear()
        clientCharacteristics.clear()
        serverSubscribers.clear()
        runCatching { gattServer?.close() }
        gattServer = null
        serverCharacteristic = null
        sessions.values.forEach(NoiseSessionLite::close)
        sessions.clear()
        if (notify) emitStatus("stopped")
    }

    fun updateNickname(value: String) {
        identity.nickname = value.trim().ifEmpty { "Emergencia-${peerId.takeLast(4)}" }
        sendAnnouncement()
    }

    fun sendPublic(content: String, channel: String? = null): String {
        check(content.isNotBlank())
        val (id, payload) = MeshProtocol.encodePublicMessage(
            nickname = nickname,
            peerId = peerId,
            content = content.take(2_000),
            channel = channel,
        )
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

    fun sendPrivate(peerIdHex: String, content: String): String {
        require(peers.containsKey(peerIdHex)) { "El dispositivo ya no está disponible" }
        val id = UUID.randomUUID().toString().uppercase()
        val session = sessions[peerIdHex]
        if (session?.established == true) {
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
        require(peers.containsKey(peerIdHex)) { "El dispositivo ya no está disponible" }
        require(frame.size <= MAX_TRANSFER_FRAME) { "Trama de transferencia demasiado grande" }
        val session = sessions[peerIdHex]
        if (session?.established == true) {
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
        val session = sessions[peerIdHex] ?: return
        val typedPayload = byteArrayOf(MeshProtocol.NOISE_TRANSFER_FRAME) + frame
        val encrypted = runCatching { session.encrypt(typedPayload) }.getOrElse {
            emitError("Falló el cifrado de la trama de transferencia")
            return
        }
        sendNoisePacket(
            MeshProtocol.TYPE_NOISE_ENCRYPTED,
            peerIdHex.hexToBytes(),
            encrypted,
        )
    }

    fun peersSnapshot(): List<Map<String, Any?>> = peers.values
        .sortedByDescending(Peer::lastSeen)
        .map {
            mapOf(
                "id" to it.id,
                "nickname" to it.nickname,
                "lastSeen" to it.lastSeen,
                "secure" to (sessions[it.id]?.established == true),
            )
        }

    fun panicWipe() {
        stop()
        storeForward.clear()
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
        radarPeerId = peerIdHex.lowercase()
        mainHandler.removeCallbacks(radarReadTask)
        mainHandler.post(radarReadTask)
    }

    fun stopRadar() {
        radarPeerId = null
        mainHandler.removeCallbacks(radarReadTask)
    }

    private val radarReadTask = object : Runnable {
        @SuppressLint("MissingPermission")
        override fun run() {
            val target = radarPeerId ?: return
            clientGatts.forEach { (address, gatt) ->
                if (addressToPeer[address] == target) {
                    runCatching { gatt.readRemoteRssi() }
                }
            }
            mainHandler.postDelayed(this, RADAR_READ_INTERVAL_MS)
        }
    }

    private fun emitRssi(peerIdHex: String, rssi: Int) {
        emit(
            mapOf(
                "type" to "rssi",
                "peerId" to peerIdHex,
                "rssi" to rssi,
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
    }

    private fun initiateHandshake(peerIdHex: String) {
        val existing = sessions[peerIdHex]
        if (existing != null) return
        val peerBytes = peerIdHex.hexToBytes()
        val session = NoiseSessionLite(peerBytes, true, identity.noisePrivateKey)
        sessions[peerIdHex] = session
        val first = runCatching { session.start() }.getOrElse {
            sessions.remove(peerIdHex)
            emitError("No se pudo iniciar el canal privado: ${it.message}")
            return
        }
        sendNoisePacket(MeshProtocol.TYPE_NOISE_HANDSHAKE, peerBytes, first)
    }

    private fun sendEncryptedPrivate(peerIdHex: String, id: String, content: String) {
        val session = sessions[peerIdHex] ?: return
        val privateData = MeshProtocol.encodePrivateMessage(id, content)
        val typedPayload = byteArrayOf(MeshProtocol.NOISE_PRIVATE_MESSAGE) + privateData
        val encrypted = runCatching { session.encrypt(typedPayload) }.getOrElse {
            emitError("Falló el cifrado del mensaje privado")
            return
        }
        sendNoisePacket(
            MeshProtocol.TYPE_NOISE_ENCRYPTED,
            peerIdHex.hexToBytes(),
            encrypted,
        )
    }

    private fun sendNoisePacket(type: Byte, recipient: ByteArray, payload: ByteArray) {
        val packet = MeshProtocol.Packet(
            type = type,
            ttl = MeshProtocol.TTL,
            timestamp = System.currentTimeMillis(),
            senderId = identity.peerId,
            recipientId = recipient,
            payload = payload,
        )
        broadcast(packet)
    }

    private fun broadcast(packet: MeshProtocol.Packet, excludeAddress: String? = null) {
        val bytes = MeshProtocol.encode(packet)
        broadcastBytes(bytes, excludeAddress)
        if (packet.recipientId != null &&
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
                    runCatching {
                        if (Build.VERSION.SDK_INT >= 33) {
                            server.notifyCharacteristicChanged(device, characteristic, false, bytes)
                        } else {
                            @Suppress("DEPRECATION")
                            characteristic.value = bytes
                            @Suppress("DEPRECATION")
                            server.notifyCharacteristicChanged(device, characteristic, false)
                        }
                    }
                }
        }
        clientCharacteristics.forEach { (address, remoteCharacteristic) ->
            if (address != excludeAddress) {
                val gatt = clientGatts[address] ?: return@forEach
                runCatching {
                    if (Build.VERSION.SDK_INT >= 33) {
                        gatt.writeCharacteristic(
                            remoteCharacteristic,
                            bytes,
                            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT,
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        remoteCharacteristic.writeType =
                            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                        @Suppress("DEPRECATION")
                        remoteCharacteristic.value = bytes
                        @Suppress("DEPRECATION")
                        gatt.writeCharacteristic(remoteCharacteristic)
                    }
                }
            }
        }
    }

    private fun receive(bytes: ByteArray, sourceAddress: String) {
        val packet = MeshProtocol.decode(bytes) ?: return
        val senderHex = MeshProtocol.hex(packet.senderId)
        // Un anuncio con TTL intacto solo puede venir del emisor original:
        // eso identifica al vecino directo detrás de esta dirección (clave
        // para el radar con iPhones, que no anuncian su peerId por BLE).
        if (packet.type == MeshProtocol.TYPE_ANNOUNCE &&
            packet.ttl == MeshProtocol.TTL &&
            senderHex != peerId
        ) {
            addressToPeer[sourceAddress] = senderHex
        }
        val fingerprint = MeshProtocol.fingerprint(packet)
        if (seen.put(fingerprint, System.currentTimeMillis()) != null) return
        if (senderHex == peerId) return

        val isForUs = packet.recipientId == null ||
            packet.recipientId.contentEquals(identity.peerId) ||
            packet.recipientId.contentEquals(MeshProtocol.broadcastRecipient)
        if (isForUs) process(packet, senderHex)

        if (packet.ttl.toInt() and 0xFF > 1 &&
            packet.type != MeshProtocol.TYPE_NOISE_HANDSHAKE &&
            packet.type != MeshProtocol.TYPE_NOISE_ENCRYPTED
        ) {
            val relayed = packet.copy(ttl = ((packet.ttl.toInt() and 0xFF) - 1).toByte())
            broadcastBytes(MeshProtocol.encode(relayed), sourceAddress)
        } else if (!isForUs && packet.ttl.toInt() and 0xFF > 1) {
            val relayed = packet.copy(ttl = ((packet.ttl.toInt() and 0xFF) - 1).toByte())
            broadcastBytes(MeshProtocol.encode(relayed), sourceAddress)
        }
    }

    private fun process(packet: MeshProtocol.Packet, senderHex: String) {
        when (packet.type) {
            MeshProtocol.TYPE_ANNOUNCE -> processAnnouncement(packet, senderHex)
            MeshProtocol.TYPE_MESSAGE -> processPublicMessage(packet, senderHex)
            MeshProtocol.TYPE_NOISE_HANDSHAKE -> processHandshake(packet, senderHex)
            MeshProtocol.TYPE_NOISE_ENCRYPTED -> processEncrypted(packet, senderHex)
        }
    }

    private fun processAnnouncement(packet: MeshProtocol.Packet, senderHex: String) {
        val announcement = MeshProtocol.decodeAnnouncement(packet.payload) ?: return
        if (!MeshProtocol.peerIdFromNoiseKey(announcement.noisePublicKey)
                .contentEquals(packet.senderId)
        ) {
            return
        }
        if (!identity.verify(packet, announcement.signingPublicKey)) return
        peers[senderHex] = Peer(
            senderHex,
            announcement.nickname,
            announcement.signingPublicKey,
        )
        emit(mapOf("type" to "peers", "peers" to peersSnapshot()))
        storeForward.forRecipient(packet.senderId).forEach(::broadcast)
    }

    private fun processPublicMessage(packet: MeshProtocol.Packet, senderHex: String) {
        val peer = peers[senderHex] ?: return
        if (!identity.verify(packet, peer.signingPublicKey)) return
        val message = MeshProtocol.decodePublicMessage(packet.payload) ?: return
        peer.lastSeen = System.currentTimeMillis()
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

    private fun processHandshake(packet: MeshProtocol.Packet, senderHex: String) {
        val session = sessions.computeIfAbsent(senderHex) {
            NoiseSessionLite(packet.senderId, false, identity.noisePrivateKey)
        }
        val response = runCatching { session.processHandshake(packet.payload) }.getOrElse {
            sessions.remove(senderHex)?.close()
            emitError("Un canal privado fue rechazado por identidad inválida")
            return
        }
        if (response != null) {
            sendNoisePacket(MeshProtocol.TYPE_NOISE_HANDSHAKE, packet.senderId, response)
        }
        if (session.established) {
            emit(mapOf("type" to "peers", "peers" to peersSnapshot()))
            pendingPrivate.remove(senderHex)?.forEach {
                sendEncryptedPrivate(senderHex, it.id, it.content)
            }
            pendingFrames.remove(senderHex)?.forEach {
                sendEncryptedFrame(senderHex, it)
            }
        }
    }

    private fun processEncrypted(packet: MeshProtocol.Packet, senderHex: String) {
        val session = sessions[senderHex]?.takeIf(NoiseSessionLite::established) ?: return
        val plaintext = runCatching { session.decrypt(packet.payload) }.getOrElse { return }
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
            emitError("El dispositivo no soporta anuncios BLE; modo solo recepción")
            emitStatus("degraded")
            return
        }
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
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
        advertiser.startAdvertising(settings, data, scanResponse, advertiseCallback)
    }

    @SuppressLint("MissingPermission")
    private fun startScanning() {
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        adapter.bluetoothLeScanner?.startScan(listOf(filter), settings, scanCallback)
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            if (!running) return
            advertising = true
            emitStatus("active")
            sendAnnouncement()
        }

        override fun onStartFailure(errorCode: Int) {
            if (!running) return
            advertising = false
            emitError(
                "No se pudo anunciar la malla BLE ($errorCode); " +
                    "otros teléfonos no verán este dispositivo, pero puede recibir",
            )
            emitStatus("degraded")
        }
    }

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
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

        override fun onScanFailed(errorCode: Int) {
            emitError("Falló el escaneo BLE ($errorCode)")
        }
    }

    private val clientCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                gatt.requestMtu(517)
                gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                clientCharacteristics.remove(gatt.device.address)
                clientGatts.remove(gatt.device.address)
                gatt.close()
            }
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val characteristic = gatt.getService(SERVICE_UUID)
                ?.getCharacteristic(CHARACTERISTIC_UUID) ?: return
            clientCharacteristics[gatt.device.address] = characteristic
            gatt.setCharacteristicNotification(characteristic, true)
            val descriptor = characteristic.getDescriptor(CLIENT_CONFIGURATION_UUID)
            if (descriptor != null) {
                if (Build.VERSION.SDK_INT >= 33) {
                    gatt.writeDescriptor(
                        descriptor,
                        BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    @Suppress("DEPRECATION")
                    gatt.writeDescriptor(descriptor)
                }
            }
            sendAnnouncement()
        }

        @Deprecated("Deprecated in Android 13")
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
            if (status != BluetoothGatt.GATT_SUCCESS) return
            val target = radarPeerId ?: return
            if (addressToPeer[gatt.device.address] == target) {
                emitRssi(target, rssi)
            }
        }
    }

    private val serverCallback = object : BluetoothGattServerCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                serverSubscribers.remove(device)
            }
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
                serverSubscribers.add(device)
                sendAnnouncement()
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
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
        emit(
            mapOf(
                "type" to "status",
                "status" to status,
                "peerId" to peerId,
                "nickname" to nickname,
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

    private companion object {
        /** Techo del plano de control BLE; los blobs van por otros transportes. */
        const val MAX_TRANSFER_FRAME = 2_048

        /** Cadencia de lectura RSSI sobre GATT conectado en modo radar. */
        const val RADAR_READ_INTERVAL_MS = 1_000L

        val SERVICE_UUID: UUID =
            UUID.fromString("F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C")
        val CHARACTERISTIC_UUID: UUID =
            UUID.fromString("A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D")
        val CLIENT_CONFIGURATION_UUID: UUID =
            UUID.fromString("00002902-0000-1000-8000-00805F9B34FB")
    }
}
