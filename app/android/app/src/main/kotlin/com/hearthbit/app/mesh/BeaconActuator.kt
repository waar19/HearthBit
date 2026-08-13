package com.hearthbit.app.mesh

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

internal class BeaconActuator(context: Context) {
    private val cameraManager = context.getSystemService(CameraManager::class.java)
    private val vibrator = if (Build.VERSION.SDK_INT >= 31) {
        context.getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Vibrator::class.java)
    }
    private val handler = Handler(Looper.getMainLooper())
    private val torchCameraId by lazy {
        runCatching {
            cameraManager?.cameraIdList?.firstOrNull { id ->
                cameraManager.getCameraCharacteristics(id)
                    .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
            }
        }.getOrNull()
    }

    private var tone: ToneGenerator? = null
    private var pulseIndex = 0
    private var flags = 0
    private var active = false
    private var expiresAt = 0L
    private var onExpired: (() -> Unit)? = null

    private val pulseTask = object : Runnable {
        override fun run() {
            if (!active || System.currentTimeMillis() >= expiresAt) {
                expire()
                return
            }
            val step = SOS_PATTERN[pulseIndex]
            pulseIndex = (pulseIndex + 1) % SOS_PATTERN.size
            applyPulse(step.on, step.durationMs)
            handler.postDelayed(this, step.durationMs)
        }
    }

    private val expiryTask = Runnable { expire() }

    fun start(flags: Int, expiresAt: Long, onExpired: () -> Unit): Boolean {
        if (flags == 0 || flags and BeaconControlProtocol.ALLOWED_FLAGS.inv() != 0) return false
        val remaining = expiresAt - System.currentTimeMillis()
        if (remaining !in 1..BeaconControlProtocol.MAX_DURATION_MS) return false
        stop()
        this.flags = flags
        this.expiresAt = expiresAt
        this.onExpired = onExpired
        active = true
        pulseIndex = 0
        if (flags and BeaconControlProtocol.FLAG_SOUND != 0) {
            tone = runCatching {
                ToneGenerator(AudioManager.STREAM_ALARM, ToneGenerator.MAX_VOLUME)
            }.getOrNull()
        }
        val hasUsableOutput =
            (flags and BeaconControlProtocol.FLAG_FLASH != 0 && torchCameraId != null) ||
                (flags and BeaconControlProtocol.FLAG_SOUND != 0 && tone != null) ||
                (flags and BeaconControlProtocol.FLAG_VIBRATE != 0 &&
                    vibrator?.hasVibrator() == true)
        if (!hasUsableOutput) {
            stop()
            return false
        }
        handler.post(pulseTask)
        handler.postDelayed(expiryTask, remaining)
        return true
    }

    fun stop() {
        active = false
        handler.removeCallbacks(pulseTask)
        handler.removeCallbacks(expiryTask)
        setTorch(false)
        runCatching { vibrator?.cancel() }
        runCatching { tone?.stopTone() }
        runCatching { tone?.release() }
        tone = null
        flags = 0
        expiresAt = 0L
        onExpired = null
    }

    fun isActive(): Boolean = active && expiresAt > System.currentTimeMillis()

    fun activeUntil(): Long = if (isActive()) expiresAt else 0L

    private fun expire() {
        if (!active) return
        val callback = onExpired
        stop()
        callback?.invoke()
    }

    private fun applyPulse(on: Boolean, durationMs: Long) {
        if (flags and BeaconControlProtocol.FLAG_FLASH != 0) setTorch(on)
        if (!on) return
        if (flags and BeaconControlProtocol.FLAG_SOUND != 0) {
            runCatching {
                tone?.startTone(
                    ToneGenerator.TONE_PROP_BEEP2,
                    durationMs.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                )
            }
        }
        if (flags and BeaconControlProtocol.FLAG_VIBRATE != 0 &&
            vibrator?.hasVibrator() == true
        ) {
            runCatching {
                vibrator.vibrate(
                    VibrationEffect.createOneShot(
                        durationMs.coerceAtMost(600),
                        VibrationEffect.DEFAULT_AMPLITUDE,
                    ),
                )
            }
        }
    }

    private fun setTorch(enabled: Boolean) {
        val cameraId = torchCameraId ?: return
        runCatching { cameraManager?.setTorchMode(cameraId, enabled) }
    }

    private data class PulseStep(val on: Boolean, val durationMs: Long)

    private companion object {
        val SOS_PATTERN = listOf(
            PulseStep(true, 200), PulseStep(false, 200),
            PulseStep(true, 200), PulseStep(false, 200),
            PulseStep(true, 200), PulseStep(false, 600),
            PulseStep(true, 600), PulseStep(false, 200),
            PulseStep(true, 600), PulseStep(false, 200),
            PulseStep(true, 600), PulseStep(false, 600),
            PulseStep(true, 200), PulseStep(false, 200),
            PulseStep(true, 200), PulseStep(false, 200),
            PulseStep(true, 200), PulseStep(false, 1_400),
        )
    }
}
