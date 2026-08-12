package com.hearthbit.app.mesh

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.hearthbit.app.MainActivity
import com.hearthbit.app.R

class MeshForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIFICATION_ID, notification())
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
