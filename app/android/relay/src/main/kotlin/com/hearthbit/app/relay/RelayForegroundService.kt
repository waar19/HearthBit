package com.hearthbit.app.relay

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.hearthbit.app.BuildConfig
import com.hearthbit.app.MainActivity
import com.hearthbit.app.R
import com.hearthbit.app.mesh.MeshRuntime

class RelayForegroundService : Service() {
    private val vehiclePowerReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (BuildConfig.VEHICLE_GATED &&
                (intent.action == Intent.ACTION_SCREEN_OFF || intent.action == Intent.ACTION_SHUTDOWN)
            ) {
                VehicleOperationGate.setSessionActive(context, false)
                stopRelay()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(
            NOTIFICATION_ID,
            notification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
        )
        if (BuildConfig.VEHICLE_GATED) {
            ContextCompat.registerReceiver(
                this,
                vehiclePowerReceiver,
                IntentFilter().apply {
                    addAction(Intent.ACTION_SCREEN_OFF)
                    addAction(Intent.ACTION_SHUTDOWN)
                },
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopRelay()
            return START_NOT_STICKY
        }
        if (BuildConfig.VEHICLE_GATED && !VehicleOperationGate.permitsRelay(this)) {
            MeshRuntime.eventListener?.invoke(
                mapOf("type" to "status", "status" to "vehicle_gated"),
            )
            stopRelay()
            return START_NOT_STICKY
        }
        val startResult = runCatching {
            val relayRole = RelayNodeRolePolicy.resolve(BuildConfig.MESH_NODE_ROLE)
            MeshRuntime.engine(this, requiredRole = relayRole).ensureStarted()
        }
        startResult.exceptionOrNull()?.let {
            MeshRuntime.eventListener?.invoke(
                mapOf(
                    "type" to "error",
                    "message" to (it.message ?: getString(R.string.error_ble_start)),
                ),
            )
            stopRelay()
            return START_NOT_STICKY
        }
        return if (BuildConfig.VEHICLE_GATED) START_NOT_STICKY else START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (BuildConfig.VEHICLE_GATED) {
            VehicleOperationGate.setSessionActive(this, false)
            stopRelay()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        if (BuildConfig.VEHICLE_GATED) {
            runCatching { unregisterReceiver(vehiclePowerReceiver) }
        }
        MeshRuntime.destroy()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun stopRelay() {
        MeshRuntime.destroy()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
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

    private fun notification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.notification_title))
            .setContentText(getString(R.string.notification_text))
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    companion object {
        const val ACTION_STOP = "com.hearthbit.relay.STOP"
        private const val CHANNEL_ID = "hearthbit_relay"
        private const val NOTIFICATION_ID = 7410
    }
}
