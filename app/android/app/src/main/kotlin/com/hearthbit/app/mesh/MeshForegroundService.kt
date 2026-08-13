package com.hearthbit.app.mesh

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
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
            MeshRuntime.destroy()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
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
            stopSelf()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(batteryReceiver) }
        if (MeshRuntime.notificationListener === notificationObserver) {
            MeshRuntime.notificationListener = null
        }
        notificationUpdateRunnable?.let(mainHandler::removeCallbacks)
        notificationUpdateRunnable = null
        MeshRuntime.destroy()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

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
            if (state == displayedNotificationState || state == pendingNotificationState) return@post
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
        val contentText = when (MeshNotificationStateReducer.contentFor(state)) {
            MeshNotificationContent.STARTING -> getString(R.string.notification_status_starting)
            MeshNotificationContent.ACTIVE -> resources.getQuantityString(
                R.plurals.notification_status_active,
                state.nearbyPeerCount,
                state.nearbyPeerCount,
            )
            MeshNotificationContent.ERROR -> getString(
                R.string.notification_status_error,
                state.errorMessage ?: getString(R.string.error_mesh_generic),
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(contentText)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    companion object {
        const val ACTION_STOP = "com.hearthbit.app.STOP_MESH"
        private const val CHANNEL_ID = "emergency_mesh"
        private const val NOTIFICATION_ID = 7401
        private const val MIN_NOTIFICATION_UPDATE_INTERVAL_MS = 2_000L
    }
}
