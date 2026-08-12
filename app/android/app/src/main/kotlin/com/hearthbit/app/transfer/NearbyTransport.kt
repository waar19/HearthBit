package com.hearthbit.app.transfer

import android.content.Context
import com.google.android.gms.nearby.Nearby
import com.hearthbit.app.R
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.ConnectionsStatusCodes
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import java.io.File

/**
 * Transporte Nearby Connections (punto a punto, sin infraestructura).
 *
 * El `transferId` (16 bytes hex negociado por BLE dentro de Noise) actúa como
 * nombre de rendezvous: el emisor anuncia con él y el receptor solo se conecta
 * al endpoint que lo anuncia. El contenido viaja además cifrado de extremo a
 * extremo (contenedor HBT), así que Nearby solo ve bytes opacos.
 */
internal class NearbyTransport(
    private val context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val client get() = Nearby.getConnectionsClient(context)

    @Volatile
    private var transferId: String? = null

    @Volatile
    private var sending = false

    @Volatile
    private var sourcePath: String? = null

    @Volatile
    private var destinationPath: String? = null

    @Volatile
    private var connectedEndpoint: String? = null

    fun sendFile(transferId: String, filePath: String) {
        stop()
        this.transferId = transferId
        sending = true
        sourcePath = filePath
        val options = AdvertisingOptions.Builder()
            .setStrategy(Strategy.P2P_POINT_TO_POINT)
            .build()
        client.startAdvertising(transferId, SERVICE_ID, connectionCallback, options)
            .addOnFailureListener {
                error(transferId, context.getString(R.string.error_nearby_advertise, it.message))
            }
    }

    fun receiveFile(transferId: String, destination: String) {
        stop()
        this.transferId = transferId
        sending = false
        destinationPath = destination
        val options = DiscoveryOptions.Builder()
            .setStrategy(Strategy.P2P_POINT_TO_POINT)
            .build()
        client.startDiscovery(SERVICE_ID, discoveryCallback, options)
            .addOnFailureListener {
                error(transferId, context.getString(R.string.error_nearby_discover, it.message))
            }
    }

    fun stop() {
        transferId = null
        connectedEndpoint = null
        runCatching { client.stopAdvertising() }
        runCatching { client.stopDiscovery() }
        runCatching { client.stopAllEndpoints() }
    }

    private fun error(transferId: String, message: String) {
        emit(
            mapOf(
                "type" to "nearbyError",
                "transferId" to transferId,
                "message" to message,
            ),
        )
    }

    private val discoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            val id = transferId ?: return
            if (info.endpointName != id) return
            client.requestConnection(id, endpointId, connectionCallback)
                .addOnFailureListener {
                    error(id, context.getString(R.string.error_nearby_rejected, it.message))
                }
        }

        override fun onEndpointLost(endpointId: String) {}
    }

    private val connectionCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            val id = transferId ?: return
            if (info.endpointName != id) {
                client.rejectConnection(endpointId)
                return
            }
            client.acceptConnection(endpointId, payloadCallback)
        }

        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            val id = transferId ?: return
            if (result.status.statusCode != ConnectionsStatusCodes.STATUS_OK) {
                error(
                    id,
                    context.getString(
                        R.string.error_nearby_not_connected,
                        result.status.statusCode,
                    ),
                )
                return
            }
            connectedEndpoint = endpointId
            if (sending) {
                val path = sourcePath ?: return
                runCatching {
                    client.sendPayload(endpointId, Payload.fromFile(File(path)))
                }.onFailure {
                    error(id, context.getString(R.string.error_nearby_send, it.message))
                }
            }
        }

        override fun onDisconnected(endpointId: String) {
            if (endpointId == connectedEndpoint) connectedEndpoint = null
        }
    }

    private val payloadCallback = object : PayloadCallback() {
        private val incoming = mutableMapOf<Long, Payload>()

        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            if (payload.type == Payload.Type.FILE) {
                incoming[payload.id] = payload
            }
        }

        override fun onPayloadTransferUpdate(
            endpointId: String,
            update: PayloadTransferUpdate,
        ) {
            val id = transferId ?: return
            when (update.status) {
                PayloadTransferUpdate.Status.IN_PROGRESS -> emit(
                    mapOf(
                        "type" to "nearbyProgress",
                        "transferId" to id,
                        "bytes" to update.bytesTransferred,
                        "total" to update.totalBytes,
                    ),
                )
                PayloadTransferUpdate.Status.SUCCESS -> {
                    if (sending) {
                        emit(mapOf("type" to "nearbyDone", "transferId" to id))
                        return
                    }
                    val payload = incoming.remove(update.payloadId) ?: return
                    val destination = destinationPath ?: return
                    runCatching {
                        val uri = requireNotNull(payload.asFile()?.asUri())
                        context.contentResolver.openInputStream(uri)!!.use { input ->
                            File(destination).outputStream().use(input::copyTo)
                        }
                        context.contentResolver.delete(uri, null, null)
                    }.onSuccess {
                        emit(mapOf("type" to "nearbyDone", "transferId" to id))
                    }.onFailure {
                        error(id, context.getString(R.string.error_nearby_save, it.message))
                    }
                }
                PayloadTransferUpdate.Status.FAILURE,
                PayloadTransferUpdate.Status.CANCELED,
                -> error(
                    id,
                    context.getString(R.string.error_nearby_interrupted, update.status),
                )
                else -> {}
            }
        }
    }

    private companion object {
        const val SERVICE_ID = "com.hearthbit.app"
    }
}
