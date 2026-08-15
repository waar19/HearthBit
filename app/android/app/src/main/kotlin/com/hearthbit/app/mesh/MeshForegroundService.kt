package com.hearthbit.app.mesh

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.hearthbit.app.MainActivity
import com.hearthbit.app.R

class MeshForegroundService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val notificationObserver: (MeshNotificationState) -> Unit = ::scheduleNotification
    private var displayedNotificationState: MeshNotificationState? = null
    private var pendingNotificationState: MeshNotificationState? = null
    private var notificationUpdateRunnable: Runnable? = null
    private var lastNotificationUpdateAt = 0L
    private val rescueStore by lazy { RescueModeStore(this) }
    private var rescueRunnable: Runnable? = null
    private var rescueLocationCancellation: CancellationSignal? = null
    private var rescuePingInProgress = false
    private var rescueGeneration = 0L
    private var bluetoothReceiverRegistered = false
    private var bluetoothAvailable = false
    private var alarmSecurityDiagnosticReported = false
    private val rescueAlarmManager by lazy {
        getSystemService(AlarmManager::class.java)
    }

    private val bluetoothStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != BluetoothAdapter.ACTION_STATE_CHANGED) return
            when (
                intent.getIntExtra(
                    BluetoothAdapter.EXTRA_STATE,
                    BluetoothAdapter.ERROR,
                )
            ) {
                BluetoothAdapter.STATE_TURNING_OFF,
                BluetoothAdapter.STATE_OFF,
                -> suspendForBluetoothOff()
                BluetoothAdapter.STATE_ON -> resumeAfterBluetoothOn()
            }
        }
    }

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val battery = if (intent?.action == Intent.ACTION_BATTERY_CHANGED) {
                intent
            } else {
                registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            }
            val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            if (level >= 0 && scale > 0) {
                val status = battery?.getIntExtra(
                    BatteryManager.EXTRA_STATUS,
                    BatteryManager.BATTERY_STATUS_UNKNOWN,
                ) ?: BatteryManager.BATTERY_STATUS_UNKNOWN
                val charging =
                    status == BatteryManager.BATTERY_STATUS_CHARGING ||
                        status == BatteryManager.BATTERY_STATUS_FULL
                val powerManager = getSystemService(PowerManager::class.java)
                val screenOn = powerManager?.isInteractive != false
                MeshRuntime.engine(this@MeshForegroundService)
                    .updatePowerState(
                        percent = level * 100 / scale,
                        isCharging = charging,
                        isScreenOn = screenOn,
                        isSystemPowerSave = powerManager?.isPowerSaveMode == true,
                    )
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        bluetoothAvailable = runCatching {
            getSystemService(BluetoothManager::class.java)?.adapter?.isEnabled == true
        }.getOrDefault(false)
        registerBluetoothStateReceiver()
        registerReceiver(
            batteryReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_BATTERY_CHANGED)
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
            },
        )
        createChannel()
        MeshRuntime.notificationListener = notificationObserver
        val startingState = MeshNotificationState(
            status = "starting",
            nearbyPeerCount = 0,
        )
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(
                NOTIFICATION_ID,
                notification(startingState),
                foregroundServiceTypes(),
            )
        } else {
            startForeground(NOTIFICATION_ID, notification(startingState))
        }
        displayedNotificationState = startingState
        lastNotificationUpdateAt = SystemClock.elapsedRealtime()
    }

    /**
     * El tipo `location` solo puede declararse si el permiso de ubicación ya
     * está concedido; con él, el SO permite leer GPS con la app en segundo
     * plano (SOS del modo rescate) mientras el servicio siga vivo.
     */
    private fun foregroundServiceTypes(): Int {
        var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
        val fine = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        if (fine || coarse) {
            types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
        }
        return types
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            cancelRescueScheduling(cancelAlarm = true)
            MeshRuntime.destroy()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_RENOTIFY) {
            val runtimeStatus = MeshRuntime.stateSnapshot()?.get("status") as? String
            if (runtimeStatus == null || runtimeStatus == "stopped") {
                stopSelf()
                return START_NOT_STICKY
            }
            val state = pendingNotificationState
                ?: displayedNotificationState
                ?: MeshNotificationState(status = "starting", nearbyPeerCount = 0)
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, notification(state))
            displayedNotificationState = state
            lastNotificationUpdateAt = SystemClock.elapsedRealtime()
            return START_STICKY
        }
        if (bluetoothAvailable) {
            startMeshEngine()
        } else {
            MeshRuntime.engine(this).suspendForBluetoothUnavailable()
        }
        if (intent?.action == ACTION_RESCUE_ALARM) {
            handleRescueAlarm()
        } else {
            scheduleRescueMode()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        if (bluetoothReceiverRegistered) {
            runCatching { unregisterReceiver(bluetoothStateReceiver) }
            bluetoothReceiverRegistered = false
        }
        runCatching { unregisterReceiver(batteryReceiver) }
        if (MeshRuntime.notificationListener === notificationObserver) {
            MeshRuntime.notificationListener = null
        }
        notificationUpdateRunnable?.let(mainHandler::removeCallbacks)
        notificationUpdateRunnable = null
        cancelRescueScheduling(cancelAlarm = false)
        MeshRuntime.destroy()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun registerBluetoothStateReceiver() {
        if (bluetoothReceiverRegistered) return
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(
                bluetoothStateReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            registerReceiver(bluetoothStateReceiver, filter)
        }
        bluetoothReceiverRegistered = true
    }

    private fun startMeshEngine() {
        runCatching { MeshRuntime.engine(this).ensureStarted() }.onFailure {
            val message = it.message ?: getString(R.string.error_ble_start)
            MeshRuntime.eventListener?.invoke(
                mapOf(
                    "type" to "error",
                    "message" to message,
                ),
            )
            MeshRuntime.eventListener?.invoke(
                mapOf("type" to "status", "status" to "error"),
            )
            scheduleNotification(
                MeshNotificationState(
                    status = "error",
                    nearbyPeerCount = 0,
                    errorMessage = message,
                ),
            )
        }
    }

    private fun suspendForBluetoothOff() {
        if (!bluetoothAvailable) return
        bluetoothAvailable = false
        cancelRescueScheduling(cancelAlarm = false)
        MeshRuntime.engine(this).suspendForBluetoothUnavailable()
        scheduleRescueMode()
    }

    private fun resumeAfterBluetoothOn() {
        if (bluetoothAvailable) return
        bluetoothAvailable = true
        startMeshEngine()
        scheduleRescueMode()
    }

    private fun cancelRescueScheduling(cancelAlarm: Boolean) {
        rescueGeneration += 1
        rescueRunnable?.let(mainHandler::removeCallbacks)
        rescueRunnable = null
        rescueLocationCancellation?.cancel()
        rescueLocationCancellation = null
        rescuePingInProgress = false
        if (cancelAlarm) {
            cancelRescueAlarm()
        }
    }

    private fun createChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.notification_channel_description)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun scheduleNotification(state: MeshNotificationState) {
        mainHandler.post {
            if (state == pendingNotificationState) return@post
            if (state == displayedNotificationState && notificationUpdateRunnable == null) return@post
            pendingNotificationState = state
            if (notificationUpdateRunnable != null) return@post
            val elapsed = SystemClock.elapsedRealtime() - lastNotificationUpdateAt
            val delay = (MIN_NOTIFICATION_UPDATE_INTERVAL_MS - elapsed).coerceAtLeast(0L)
            notificationUpdateRunnable = Runnable {
                notificationUpdateRunnable = null
                val next = pendingNotificationState ?: return@Runnable
                pendingNotificationState = null
                if (next == displayedNotificationState) return@Runnable
                getSystemService(NotificationManager::class.java)
                    .notify(NOTIFICATION_ID, notification(next))
                displayedNotificationState = next
                lastNotificationUpdateAt = SystemClock.elapsedRealtime()
            }.also { mainHandler.postDelayed(it, delay) }
        }
    }

    private fun notification(state: MeshNotificationState): Notification {
        val openIntent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val deleteIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, MeshForegroundService::class.java).setAction(ACTION_RENOTIFY),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val contentText = when (MeshNotificationStateReducer.contentFor(state)) {
            MeshNotificationContent.STARTING -> getString(R.string.notification_status_starting)
            MeshNotificationContent.ACTIVE -> resources.getQuantityString(
                R.plurals.notification_status_active,
                state.nearbyPeerCount,
                state.nearbyPeerCount,
            )
            MeshNotificationContent.ERROR -> getString(R.string.notification_status_error)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(contentText)
            .setContentIntent(pendingIntent)
            .setDeleteIntent(deleteIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun scheduleRescueMode() {
        rescueRunnable?.let(mainHandler::removeCallbacks)
        rescueRunnable = null
        val now = System.currentTimeMillis()
        val state = rescueStore.read(now)
        MeshRuntime.engine(this).updateRescueModeState(state)
        if (!state.active) {
            cancelRescueScheduling(cancelAlarm = true)
            return
        }
        if (rescuePingInProgress) return
        if (!bluetoothAvailable) {
            RescueAlarmPolicy.retryWhenRadioUnavailable(
                now = now,
                intervalMs = state.intervalMs,
                expiresAt = state.expiresAt,
            )?.let(::scheduleRescueAlarm)
            return
        }
        val nextAt = RescueAlarmPolicy.nextDue(
            lastPingAt = state.lastPingAt,
            intervalMs = state.intervalMs,
            now = now,
        )
        val wakeAt = RescueAlarmPolicy.nextWakeAt(
            active = state.active,
            expiresAt = state.expiresAt,
            nextDueAt = nextAt,
            now = now,
        ) ?: return
        scheduleRescueAlarm(wakeAt)
        rescueRunnable = Runnable {
            rescueRunnable = null
            runRescuePing()
        }.also {
            mainHandler.postDelayed(it, (wakeAt - now).coerceAtLeast(0L))
        }
    }

    private fun handleRescueAlarm() {
        val now = System.currentTimeMillis()
        val state = rescueStore.read(now)
        MeshRuntime.engine(this).updateRescueModeState(state)
        if (!state.active) {
            cancelRescueScheduling(cancelAlarm = true)
            return
        }
        if (!bluetoothAvailable) {
            rescueRunnable?.let(mainHandler::removeCallbacks)
            rescueRunnable = null
            RescueAlarmPolicy.retryWhenRadioUnavailable(
                now = now,
                intervalMs = state.intervalMs,
                expiresAt = state.expiresAt,
            )?.let(::scheduleRescueAlarm)
            return
        }
        val nextAt = RescueAlarmPolicy.nextDue(
            lastPingAt = state.lastPingAt,
            intervalMs = state.intervalMs,
            now = now,
        )
        if (RescueAlarmPolicy.shouldPing(state.active, state.expiresAt, nextAt, now)) {
            runRescuePing()
        } else {
            scheduleRescueMode()
        }
    }

    private fun runRescuePing() {
        if (rescuePingInProgress) return
        val now = System.currentTimeMillis()
        val state = rescueStore.read(now)
        MeshRuntime.engine(this).updateRescueModeState(state)
        if (!state.active || !bluetoothAvailable) {
            scheduleRescueMode()
            return
        }
        val nextAt = RescueAlarmPolicy.nextDue(
            lastPingAt = state.lastPingAt,
            intervalMs = state.intervalMs,
            now = now,
        )
        if (!RescueAlarmPolicy.shouldPing(state.active, state.expiresAt, nextAt, now)) {
            scheduleRescueMode()
            return
        }
        val generation = rescueGeneration
        rescuePingInProgress = true
        val deliver: (Location?) -> Unit = deliver@{ location ->
            if (generation != rescueGeneration) return@deliver
            val timestamp = System.currentTimeMillis()
            runCatching {
                val engine = MeshRuntime.engine(this)
                engine.ensureStarted()
                engine.setRadarConsent(
                    enabled = true,
                    durationMs = RadarConsentProtocol.SOS_DURATION_MS,
                )
                val latitude = when (state.locationPrecision) {
                    RescueModeStore.LOCATION_NONE -> null
                    RescueModeStore.LOCATION_APPROXIMATE ->
                        location?.latitude?.let(::coarsenEmergencyCoordinate)
                    else -> location?.latitude
                }
                val longitude = when (state.locationPrecision) {
                    RescueModeStore.LOCATION_NONE -> null
                    RescueModeStore.LOCATION_APPROXIMATE ->
                        location?.longitude?.let(::coarsenEmergencyCoordinate)
                    else -> location?.longitude
                }
                engine.sendSos(state.description, latitude, longitude)
            }.onSuccess {
                rescueStore.recordPing(timestamp)
                MeshRuntime.eventListener?.invoke(
                    mapOf("type" to "rescuePing", "timestamp" to timestamp),
                )
            }.onFailure {
                MeshRuntime.eventListener?.invoke(
                    mapOf(
                        "type" to "error",
                        "message" to (it.message ?: getString(R.string.error_ble_start)),
                    ),
                )
            }
            rescuePingInProgress = false
            scheduleRescueMode()
        }
        if (state.locationPrecision == RescueModeStore.LOCATION_NONE) {
            deliver(null)
        } else {
            currentRescueLocation(deliver)
        }
    }

    private fun scheduleRescueAlarm(triggerAtMillis: Long) {
        try {
            rescueAlarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMillis,
                rescueAlarmPendingIntent(),
            )
        } catch (exception: SecurityException) {
            reportAlarmSecurityException("schedule", exception)
        }
    }

    private fun cancelRescueAlarm() {
        try {
            rescueAlarmManager.cancel(rescueAlarmPendingIntent())
        } catch (exception: SecurityException) {
            reportAlarmSecurityException("cancel", exception)
        }
    }

    private fun rescueAlarmPendingIntent(): PendingIntent = PendingIntent.getForegroundService(
        this,
        RESCUE_ALARM_REQUEST_CODE,
        Intent(this, MeshForegroundService::class.java).setAction(ACTION_RESCUE_ALARM),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun reportAlarmSecurityException(operation: String, exception: SecurityException) {
        if (alarmSecurityDiagnosticReported) return
        alarmSecurityDiagnosticReported = true
        val detail = exception.message.orEmpty().take(MAX_ALARM_DIAGNOSTIC_LENGTH)
        val message = "Rescue alarm $operation unavailable: $detail"
        Log.w(TAG, message, exception)
        MeshRuntime.eventListener?.invoke(
            mapOf(
                "type" to "diagnostic",
                "component" to "rescueAlarm",
                "message" to message,
            ),
        )
    }

    private fun coarsenEmergencyCoordinate(value: Double): Double =
        kotlin.math.round(value * 1_000.0) / 1_000.0

    private fun currentRescueLocation(onResult: (Location?) -> Unit) {
        val fine = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) {
            onResult(null)
            return
        }
        val manager = getSystemService(LocationManager::class.java)
        val fallback = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
        ).mapNotNull { provider ->
            runCatching { manager?.getLastKnownLocation(provider) }.getOrNull()
        }.maxByOrNull(Location::getTime)
        if (Build.VERSION.SDK_INT < 30 || !fine) {
            onResult(fallback)
            return
        }
        val cancellation = CancellationSignal()
        rescueLocationCancellation?.cancel()
        rescueLocationCancellation = cancellation
        var completed = false
        fun complete(location: Location?) {
            if (completed) return
            completed = true
            rescueLocationCancellation = null
            onResult(location ?: fallback)
        }
        mainHandler.postDelayed({
            cancellation.cancel()
            complete(null)
        }, RESCUE_LOCATION_TIMEOUT_MS)
        runCatching {
            manager?.getCurrentLocation(
                LocationManager.GPS_PROVIDER,
                cancellation,
                mainExecutor,
                ::complete,
            ) ?: complete(null)
        }.onFailure { complete(null) }
    }

    companion object {
        const val ACTION_STOP = "com.hearthbit.app.STOP_MESH"
        const val ACTION_RENOTIFY = "com.hearthbit.app.RENOTIFY_MESH"
        const val ACTION_RESCUE_CHANGED = "com.hearthbit.app.RESCUE_CHANGED"
        const val ACTION_RESCUE_ALARM = "com.hearthbit.app.RESCUE_ALARM"
        private const val CHANNEL_ID = "emergency_mesh"
        private const val NOTIFICATION_ID = 7401
        private const val RESCUE_ALARM_REQUEST_CODE = 2
        private const val MIN_NOTIFICATION_UPDATE_INTERVAL_MS = 2_000L
        private const val RESCUE_LOCATION_TIMEOUT_MS = 10_000L
        private const val MAX_ALARM_DIAGNOSTIC_LENGTH = 160
        private const val TAG = "MeshForegroundService"
    }
}
