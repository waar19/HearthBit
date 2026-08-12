package com.hearthbit.app.mesh

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.hearthbit.app.MainActivity
import com.hearthbit.app.R

class MeshForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        createChannel()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIFICATION_ID, notification(), foregroundServiceTypes())
        } else {
            startForeground(NOTIFICATION_ID, notification())
        }
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
        runCatching { MeshRuntime.engine(this).start() }.onFailure {
            MeshRuntime.eventListener?.invoke(
                mapOf("type" to "error", "message" to (it.message ?: "No se pudo iniciar BLE")),
            )
            MeshRuntime.eventListener?.invoke(
                mapOf("type" to "status", "status" to "error"),
            )
            stopSelf()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        MeshRuntime.destroy()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Malla de emergencia",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Mantiene la conexión Bluetooth activa durante una emergencia"
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun notification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("HearthBit está conectado")
            .setContentText("Retransmitiendo mensajes de la malla BLE")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    companion object {
        const val ACTION_STOP = "com.hearthbit.app.STOP_MESH"
        private const val CHANNEL_ID = "emergency_mesh"
        private const val NOTIFICATION_ID = 7401
    }
}
