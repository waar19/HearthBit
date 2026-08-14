package com.hearthbit.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.net.wifi.aware.WifiAwareManager
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.hearthbit.app.mesh.AdaptivePowerPolicy
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
    private var backgroundLocationResult: MethodChannel.Result? = null
    private var familyNotificationPermissionResult: MethodChannel.Result? = null
    private var transferEvents: EventChannel.EventSink? = null
    private var lanMulticastLock: WifiManager.MulticastLock? = null
    private var emergencyShortcutChannel: MethodChannel? = null
    private var emergencyShortcutPending = false
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

    override fun onDestroy() {
        setLanMulticastEnabled(false)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        emergencyShortcutPending = intent?.action == ACTION_OPEN_EMERGENCY
        emergencyShortcutChannel = MethodChannel(messenger, EMERGENCY_SHORTCUT_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeInitialOpen" -> {
                        result.success(emergencyShortcutPending)
                        emergencyShortcutPending = false
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCapabilities" -> result.success(
                    mapOf(
                        "platform" to "android",
                        "backgroundRelay" to true,
                        "peripheralMode" to true,
                        "acousticSonar" to true,
                        "radioRanging" to (Build.VERSION.SDK_INT >= 36),
                        "nodeRoles" to listOf(
                            "PHONE_RELAY",
                            "PHONE_BEACON",
                            "INFRA_RELAY",
                            "INFRA_DATA_ANCHOR",
                        ),
                    ),
                )
                "getInstalledApkForShare" -> prepareInstalledApk(result)
                "requestPermissions" -> requestMeshPermissions(result)
                "requestFamilyNotificationPermission" ->
                    requestFamilyNotificationPermission(result)
                "showFamilyNotification" -> runMethod(result) {
                    showFamilyNotification(
                        messageId = requireNotNull(call.argument<String>("messageId")),
                        nickname = requireNotNull(call.argument<String>("nickname")),
                        status = requireNotNull(call.argument<String>("status")),
                    )
                    null
                }
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
                "configureLanBridge" -> runMethod(result) {
                    MeshRuntime.engine(this).configureLanBridge(
                        enabled = call.argument<Boolean>("enabled") == true,
                        gatewayId = call.argument<String>("gatewayId"),
                        maxFrameSize = call.argument<Number>("maxFrameSize")?.toInt() ?: 2_048,
                    )
                    null
                }
                "setLanDiscoveryEnabled" -> runMethod(result) {
                    setLanMulticastEnabled(call.argument<Boolean>("enabled") == true)
                    null
                }
                "injectRawMeshFrame" -> runMethod(result) {
                    MeshRuntime.engine(this).injectRawMeshFrame(
                        gatewayId = requireNotNull(call.argument<String>("gatewayId")),
                        frame = requireNotNull(call.argument<ByteArray>("frame")),
                    )
                    null
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
                        call.argument<String>("messageId"),
                    )
                }
                "ensurePrivateChannel" -> runMethod(result) {
                    MeshRuntime.engine(this).ensurePrivateChannel(
                        requireNotNull(call.argument<String>("peerId")),
                    )
                    null
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
                "setNodeRole" -> runMethod(result) {
                    MeshRuntime.engine(this).updateRole(
                        requireNotNull(call.argument<String>("role")),
                    )
                    null
                }
                "setGenericPresenceScanEnabled" -> runMethod(result) {
                    MeshRuntime.engine(this).setGenericPresenceScanEnabled(
                        call.argument<Boolean>("enabled") == true,
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
                "sendRangingControl" -> runMethod(result) {
                    MeshRuntime.engine(this).sendRangingControl(
                        requireNotNull(call.argument<String>("peerId")),
                        requireNotNull(call.argument<ByteArray>("payload")),
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
                "startRadar" -> runMethod(result) {
                    MeshRuntime.engine(this).startRadar(
                        requireNotNull(call.argument<String>("peerId")),
                    )
                    null
                }
                "getRangingCapabilities" -> runMethod(result) {
                    MeshRuntime.engine(this).rangingCapabilities()
                }
                "startRadioRanging" -> runMethod(result) {
                    MeshRuntime.engine(this).startRadioRanging(
                        requireNotNull(call.argument<String>("peerId")),
                    )
                    null
                }
                "stopRadioRanging" -> runMethod(result) {
                    MeshRuntime.engine(this).stopRadioRanging()
                    null
                }
                "stopRadar" -> runMethod(result) {
                    MeshRuntime.engine(this).stopRadar()
                    null
                }
                "setRadarConsent" -> runMethod(result) {
                    val minutes = (call.argument<Number>("minutes")?.toLong() ?: 15L)
                    MeshRuntime.engine(this).setRadarConsent(
                        enabled = call.argument<Boolean>("enabled") == true,
                        durationMs = minutes.coerceIn(1L, 20L) * 60_000L,
                    )
                    null
                }
                "startLocalBeacon" -> runMethod(result) {
                    MeshRuntime.engine(this).startLocalBeacon(
                        flags = call.argument<Number>("flags")?.toInt() ?: 0x07,
                        durationMs = (call.argument<Number>("durationSeconds")?.toLong() ?: 300L)
                            .coerceIn(1L, 300L) * 1_000L,
                    )
                    null
                }
                "stopLocalBeacon" -> runMethod(result) {
                    MeshRuntime.engine(this).stopLocalBeacon()
                    null
                }
                "requestRemoteBeacon" -> runMethod(result) {
                    MeshRuntime.engine(this).requestRemoteBeacon(
                        peerIdHex = requireNotNull(call.argument<String>("peerId")),
                        flags = call.argument<Number>("flags")?.toInt() ?: 0x07,
                        durationMs = (call.argument<Number>("durationSeconds")?.toLong() ?: 300L)
                            .coerceIn(1L, 300L) * 1_000L,
                    )
                }
                "respondToBeaconRequest" -> runMethod(result) {
                    MeshRuntime.engine(this).respondToBeaconRequest(
                        requestId = requireNotNull(call.argument<String>("requestId")),
                        accept = call.argument<Boolean>("accept") == true,
                    )
                    null
                }
                "stopRemoteBeacon" -> runMethod(result) {
                    MeshRuntime.engine(this).stopRemoteBeacon(
                        peerIdHex = requireNotNull(call.argument<String>("peerId")),
                        requestId = requireNotNull(call.argument<String>("requestId")),
                    )
                    null
                }
                "getPowerStatus" -> {
                    val power = getSystemService(PowerManager::class.java)
                    val batteryLevel = batteryLevel()
                    val snapshot = MeshRuntime.stateSnapshot()
                    val profile = snapshot?.get("powerProfile") as? String
                        ?: AdaptivePowerPolicy.profileFor(
                            batteryPercent = batteryLevel,
                            isCharging = isCharging(),
                            screenOn = power?.isInteractive != false,
                            systemPowerSave = power?.isPowerSaveMode == true,
                            survivalMode = false,
                        ).wireName
                    result.success(
                        mapOf(
                            "ignoringBatteryOptimizations" to
                                (power?.isIgnoringBatteryOptimizations(packageName) == true),
                            "lowPowerMode" to (power?.isPowerSaveMode == true),
                            "backgroundLocation" to backgroundLocationGranted(),
                            "batteryLevel" to batteryLevel,
                            "adaptivePowerSaving" to
                                (snapshot?.get("adaptivePowerSaving") as? Boolean
                                    ?: (profile != "performance" && profile != "balanced")),
                            "powerProfile" to profile,
                        ),
                    )
                }
                "requestDisableBatteryOptimizations" ->
                    requestDisableBatteryOptimizations(result)
                "requestBackgroundLocation" -> requestBackgroundLocation(result)
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    MeshRuntime.eventListener = { event ->
                        runOnUiThread { events.success(event) }
                    }
                    MeshRuntime.stateSnapshot()?.let { snapshot ->
                        runOnUiThread { events.success(snapshot) }
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
                    requireNotNull(wifiAwareTransport) {
                        getString(R.string.error_wifi_aware_unsupported)
                    }
                        .sendFile(
                            requireNotNull(call.argument<String>("transferId")),
                            requireNotNull(call.argument<String>("filePath")),
                        )
                    null
                }
                "wifiAwareReceiveFile" -> runMethod(result) {
                    requireNotNull(wifiAwareTransport) {
                        getString(R.string.error_wifi_aware_unsupported)
                    }
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action != ACTION_OPEN_EMERGENCY) return
        emergencyShortcutPending = true
        emergencyShortcutChannel?.invokeMethod("openEmergency", null)
    }

    private fun nearbyAvailable(): Boolean =
        GoogleApiAvailability.getInstance()
            .isGooglePlayServicesAvailable(this) == ConnectionResult.SUCCESS

    private fun setLanMulticastEnabled(enabled: Boolean) {
        if (!enabled) {
            lanMulticastLock?.let { lock ->
                if (lock.isHeld) lock.release()
            }
            lanMulticastLock = null
            return
        }
        if (lanMulticastLock?.isHeld == true) return
        val wifi = applicationContext.getSystemService(WifiManager::class.java)
        lanMulticastLock = wifi?.createMulticastLock("hearthbit-mdns")?.apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun wifiAwareAvailable(): Boolean {
        // El data path con puerto (WifiAwareNetworkSpecifier.Builder.setPort)
        // requiere API 29; en versiones anteriores se cae a Nearby/LAN/BLE.
        if (Build.VERSION.SDK_INT < 29) return false
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_AWARE)) return false
        val manager = getSystemService(WifiAwareManager::class.java)
        return manager?.isAvailable == true
    }

    private fun prepareInstalledApk(result: MethodChannel.Result) {
        Thread {
            runCatching {
                InstalledApkSharePreparer(applicationContext).prepare()
            }.onSuccess { prepared ->
                runOnUiThread { result.success(prepared) }
            }.onFailure { error ->
                runOnUiThread {
                    result.error(
                        "apk_share_error",
                        error.message ?: "Could not prepare the installed APK",
                        null,
                    )
                }
            }
        }.start()
    }

    /**
     * Muestra el diálogo del sistema para excluir a HearthBit de la
     * optimización de batería (Doze). Sin esta exclusión, Android suspende el
     * BLE y el GPS en segundo plano justo cuando más se necesitan.
     */
    private fun requestDisableBatteryOptimizations(result: MethodChannel.Result) {
        val power = getSystemService(PowerManager::class.java)
        if (power?.isIgnoringBatteryOptimizations(packageName) == true) {
            result.success(true)
            return
        }
        runCatching {
            startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.parse("package:$packageName")),
            )
        }.recoverCatching {
            // Algunos fabricantes bloquean el diálogo directo; se abre la
            // lista general para que la persona busque HearthBit.
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
        // El diálogo es asíncrono: Flutter refresca el estado al volver.
        result.success(false)
    }

    private fun fineOrCoarseLocationGranted(): Boolean =
        ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED

    private fun batteryLevel(): Int {
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        return if (level >= 0 && scale > 0) level * 100 / scale else 100
    }

    private fun isCharging(): Boolean {
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val status = battery?.getIntExtra(
            BatteryManager.EXTRA_STATUS,
            BatteryManager.BATTERY_STATUS_UNKNOWN,
        ) ?: BatteryManager.BATTERY_STATUS_UNKNOWN
        return status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL
    }

    private fun backgroundLocationGranted(): Boolean =
        if (Build.VERSION.SDK_INT < 29) {
            fineOrCoarseLocationGranted()
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
        }

    /**
     * Pide «Permitir todo el tiempo». Requiere que el permiso de primer plano
     * ya esté concedido (Android lo exige en dos pasos desde API 30).
     */
    private fun requestBackgroundLocation(result: MethodChannel.Result) {
        if (backgroundLocationGranted()) {
            result.success(true)
            return
        }
        if (!fineOrCoarseLocationGranted()) {
            result.success(false)
            return
        }
        backgroundLocationResult = result
        requestPermissions(
            arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
            BACKGROUND_LOCATION_REQUEST,
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
        if (requestCode == BACKGROUND_LOCATION_REQUEST) {
            backgroundLocationResult?.success(backgroundLocationGranted())
            backgroundLocationResult = null
        }
        if (requestCode == FAMILY_NOTIFICATION_PERMISSION_REQUEST) {
            familyNotificationPermissionResult?.success(
                grantResults.singleOrNull() == PackageManager.PERMISSION_GRANTED,
            )
            familyNotificationPermissionResult = null
        }
    }

    private fun requestFamilyNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        familyNotificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            FAMILY_NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun showFamilyNotification(messageId: String, nickname: String, status: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(
                    FAMILY_NOTIFICATION_CHANNEL,
                    getString(R.string.family_notification_channel_name),
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = getString(R.string.family_notification_channel_description)
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
                },
            )
        }
        val localizedStatus = when (status) {
            "SOS" -> getString(R.string.family_notification_status_sos)
            "OK" -> getString(R.string.family_notification_status_ok)
            "HELP" -> getString(R.string.family_notification_status_help)
            "INJURED" -> getString(R.string.family_notification_status_injured)
            else -> getString(R.string.family_notification_status_check_in)
        }
        val openEmergency = Intent(this, MainActivity::class.java)
            .setAction(ACTION_OPEN_EMERGENCY)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pendingIntent = PendingIntent.getActivity(
            this,
            messageId.hashCode(),
            openEmergency,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = if (Build.VERSION.SDK_INT >= 26) {
            android.app.Notification.Builder(this, FAMILY_NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this)
        }.setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.family_notification_title))
            .setContentText("${nickname.take(64)} · $localizedStatus")
            .setCategory(android.app.Notification.CATEGORY_ALARM)
            .setVisibility(android.app.Notification.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        manager.notify(messageId.hashCode(), notification)
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
            if (Build.VERSION.SDK_INT >= 36) {
                add(Manifest.permission.RANGING)
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
                result.error(
                    "mesh_error",
                    it.message ?: getString(R.string.error_mesh_generic),
                    null,
                )
            }
    }

    private companion object {
        const val METHOD_CHANNEL = "com.hearthbit.mesh/methods"
        const val EVENT_CHANNEL = "com.hearthbit.mesh/events"
        const val TRANSFER_METHOD_CHANNEL = "com.hearthbit.transfer/methods"
        const val TRANSFER_EVENT_CHANNEL = "com.hearthbit.transfer/events"
        const val EMERGENCY_SHORTCUT_CHANNEL = "com.hearthbit.emergency/shortcut"
        const val ACTION_OPEN_EMERGENCY = "com.hearthbit.app.OPEN_EMERGENCY"
        const val PERMISSION_REQUEST = 7402
        const val BACKGROUND_LOCATION_REQUEST = 7403
        const val FAMILY_NOTIFICATION_PERMISSION_REQUEST = 7404
        const val FAMILY_NOTIFICATION_CHANNEL = "family_emergency"
    }
}
