package com.hearthbit.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.aware.WifiAwareManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.hearthbit.app.mesh.MeshForegroundService
import com.hearthbit.app.mesh.MeshRuntime
import com.hearthbit.app.transfer.NearbyTransport
import com.hearthbit.app.transfer.WifiAwareTransport
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var transferEvents: EventChannel.EventSink? = null
    private val nearbyTransport by lazy {
        NearbyTransport(applicationContext) { event ->
            runOnUiThread { transferEvents?.success(event) }
        }
    }
    private val wifiAwareTransport by lazy {
        if (Build.VERSION.SDK_INT >= 29) {
            WifiAwareTransport(applicationContext) { event ->
                runOnUiThread { transferEvents?.success(event) }
            }
        } else {
            null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCapabilities" -> result.success(
                    mapOf(
                        "platform" to "android",
                        "backgroundRelay" to true,
                        "peripheralMode" to true,
                    ),
                )
                "requestPermissions" -> requestMeshPermissions(result)
                "startMesh" -> {
                    ContextCompat.startForegroundService(
                        this,
                        Intent(this, MeshForegroundService::class.java),
                    )
                    result.success(null)
                }
                "stopMesh" -> {
                    startService(
                        Intent(this, MeshForegroundService::class.java)
                            .setAction(MeshForegroundService.ACTION_STOP),
                    )
                    result.success(null)
                }
                "sendPublic" -> runMethod(result) {
                    MeshRuntime.engine(this).sendPublic(
                        call.argument<String>("content").orEmpty(),
                        call.argument<String>("channel"),
                    )
                }
                "sendPrivate" -> runMethod(result) {
                    MeshRuntime.engine(this).sendPrivate(
                        requireNotNull(call.argument<String>("peerId")),
                        call.argument<String>("content").orEmpty(),
                    )
                }
                "sendSos" -> runMethod(result) {
                    MeshRuntime.engine(this).sendSos(
                        call.argument<String>("content").orEmpty(),
                        call.argument<Double>("latitude"),
                        call.argument<Double>("longitude"),
                    )
                }
                "setNickname" -> runMethod(result) {
                    MeshRuntime.engine(this).updateNickname(
                        call.argument<String>("nickname").orEmpty(),
                    )
                    null
                }
                "getPeers" -> runMethod(result) {
                    MeshRuntime.engine(this).peersSnapshot()
                }
                "sendTransferFrame" -> runMethod(result) {
                    MeshRuntime.engine(this).sendTransferFrame(
                        requireNotNull(call.argument<String>("peerId")),
                        requireNotNull(call.argument<ByteArray>("frame")),
                    )
                    null
                }
                "signPayload" -> runMethod(result) {
                    MeshRuntime.engine(this).signPayload(
                        requireNotNull(call.argument<ByteArray>("data")),
                    )
                }
                "verifyPeerSignature" -> runMethod(result) {
                    MeshRuntime.engine(this).verifyPeerSignature(
                        requireNotNull(call.argument<String>("peerId")),
                        requireNotNull(call.argument<ByteArray>("data")),
                        requireNotNull(call.argument<ByteArray>("signature")),
                    )
                }
                "panicWipe" -> runMethod(result) {
                    MeshRuntime.engine(this).panicWipe()
                    MeshRuntime.destroy()
                    null
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    MeshRuntime.eventListener = { event ->
                        runOnUiThread { events.success(event) }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    MeshRuntime.eventListener = null
                }
            },
        )

        MethodChannel(messenger, TRANSFER_METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTransferCapabilities" -> result.success(
                    mapOf(
                        "nearby" to nearbyAvailable(),
                        "wifiAware" to wifiAwareAvailable(),
                    ),
                )
                "nearbySendFile" -> runMethod(result) {
                    nearbyTransport.sendFile(
                        requireNotNull(call.argument<String>("transferId")),
                        requireNotNull(call.argument<String>("filePath")),
                    )
                    null
                }
                "nearbyReceiveFile" -> runMethod(result) {
                    nearbyTransport.receiveFile(
                        requireNotNull(call.argument<String>("transferId")),
                        requireNotNull(call.argument<String>("destinationPath")),
                    )
                    null
                }
                "nearbyStop" -> runMethod(result) {
                    nearbyTransport.stop()
                    null
                }
                "wifiAwareSendFile" -> runMethod(result) {
                    requireNotNull(wifiAwareTransport) { "Wi-Fi Aware no soportado" }
                        .sendFile(
                            requireNotNull(call.argument<String>("transferId")),
                            requireNotNull(call.argument<String>("filePath")),
                        )
                    null
                }
                "wifiAwareReceiveFile" -> runMethod(result) {
                    requireNotNull(wifiAwareTransport) { "Wi-Fi Aware no soportado" }
                        .receiveFile(
                            requireNotNull(call.argument<String>("transferId")),
                            requireNotNull(call.argument<String>("destinationPath")),
                        )
                    null
                }
                "wifiAwareStop" -> runMethod(result) {
                    wifiAwareTransport?.stop()
                    null
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, TRANSFER_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    transferEvents = events
                }

                override fun onCancel(arguments: Any?) {
                    transferEvents = null
                }
            },
        )
    }

    private fun nearbyAvailable(): Boolean =
        GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(this) == ConnectionResult.SUCCESS

    private fun wifiAwareAvailable(): Boolean {
        // El data path con puerto (WifiAwareNetworkSpecifier.Builder.setPort)
        // requiere API 29; en versiones anteriores se cae a Nearby/LAN/BLE.
        if (Build.VERSION.SDK_INT < 29) return false
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_AWARE)) return false
        val manager = getSystemService(WifiAwareManager::class.java)
        return manager?.isAvailable == true
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            permissionResult?.success(granted)
            permissionResult = null
        }
    }

    private fun requestMeshPermissions(result: MethodChannel.Result) {
        val permissions = buildList {
            if (Build.VERSION.SDK_INT >= 31) {
                add(Manifest.permission.BLUETOOTH_SCAN)
                add(Manifest.permission.BLUETOOTH_CONNECT)
                add(Manifest.permission.BLUETOOTH_ADVERTISE)
            } else {
                add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
            if (Build.VERSION.SDK_INT in 31..32) {
                // Nearby Connections aún exige ubicación para descubrir por Wi-Fi.
                add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
            if (Build.VERSION.SDK_INT >= 33) {
                add(Manifest.permission.POST_NOTIFICATIONS)
                add(Manifest.permission.NEARBY_WIFI_DEVICES)
            }
        }.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (permissions.isEmpty()) {
            result.success(true)
            return
        }
        permissionResult = result
        requestPermissions(permissions.toTypedArray(), PERMISSION_REQUEST)
    }

    private fun runMethod(result: MethodChannel.Result, block: () -> Any?) {
        runCatching(block)
            .onSuccess(result::success)
            .onFailure {
                result.error("mesh_error", it.message ?: "Error de malla", null)
            }
    }

    private companion object {
        const val METHOD_CHANNEL = "com.hearthbit.mesh/methods"
        const val EVENT_CHANNEL = "com.hearthbit.mesh/events"
        const val TRANSFER_METHOD_CHANNEL = "com.hearthbit.transfer/methods"
        const val TRANSFER_EVENT_CHANNEL = "com.hearthbit.transfer/events"
        const val PERMISSION_REQUEST = 7402
    }
}
