package com.emergencycom.emergency_com

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.emergencycom.emergency_com.mesh.MeshForegroundService
import com.emergencycom.emergency_com.mesh.MeshRuntime
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null

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
            if (Build.VERSION.SDK_INT >= 33) {
                add(Manifest.permission.POST_NOTIFICATIONS)
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
        const val METHOD_CHANNEL = "com.emergencycom.mesh/methods"
        const val EVENT_CHANNEL = "com.emergencycom.mesh/events"
        const val PERMISSION_REQUEST = 7402
    }
}
