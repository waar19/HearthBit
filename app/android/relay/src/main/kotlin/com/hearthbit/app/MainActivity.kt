package com.hearthbit.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat
import com.hearthbit.app.mesh.MeshRuntime
import com.hearthbit.app.relay.BleCapabilities
import com.hearthbit.app.relay.BleCapabilityDetector
import com.hearthbit.app.relay.RelayForegroundService
import com.hearthbit.app.relay.RelayMode
import com.hearthbit.app.relay.VehicleOperationGate

class MainActivity : Activity() {
    private lateinit var modeView: TextView
    private lateinit var statusView: TextView
    private lateinit var startButton: Button
    private lateinit var stopButton: Button
    private val capabilityDetector by lazy { BleCapabilityDetector(this) }
    private val preferences by lazy {
        getSharedPreferences(PREFERENCES, MODE_PRIVATE)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(buildContent())
        renderCapabilities(capabilityDetector.detect())
        MeshRuntime.eventListener = { event ->
            runOnUiThread { renderMeshEvent(event) }
        }
        MeshRuntime.stateSnapshot()?.let(::renderMeshEvent)
    }

    override fun onStart() {
        super.onStart()
        if (BuildConfig.VEHICLE_GATED && preferences.getBoolean(USER_ENABLED, false)) {
            VehicleOperationGate.setSessionActive(this, true)
            if (hasMeshPermissions(capabilityDetector.detect().mode)) {
                startRelayService()
            }
        }
    }

    override fun onStop() {
        if (BuildConfig.VEHICLE_GATED) {
            VehicleOperationGate.setSessionActive(this, false)
            stopRelayService()
            statusView.setText(R.string.relay_status_vehicle_gate)
        }
        super.onStop()
    }

    override fun onDestroy() {
        MeshRuntime.eventListener = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return
        val capabilities = capabilityDetector.detect()
        renderCapabilities(capabilities)
        if (hasMeshPermissions(capabilities.mode)) {
            beginRelay()
        } else {
            statusView.setText(R.string.relay_permission_denied)
        }
    }

    private fun buildContent(): LinearLayout {
        val padding = (32 * resources.displayMetrics.density).toInt()
        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(padding, padding, padding, padding)
            setBackgroundColor(Color.rgb(16, 24, 32))
        }
        val title = TextView(this).apply {
            setText(
                if (BuildConfig.VEHICLE_GATED) {
                    R.string.relay_title_automotive
                } else {
                    R.string.relay_title_tv
                },
            )
            textSize = 32f
            setTextColor(Color.WHITE)
        }
        val description = TextView(this).apply {
            setText(
                if (BuildConfig.VEHICLE_GATED) {
                    R.string.relay_description_automotive
                } else {
                    R.string.relay_description_tv
                },
            )
            textSize = 18f
            setTextColor(Color.LTGRAY)
            setPadding(0, padding / 2, 0, padding)
        }
        modeView = TextView(this).apply {
            textSize = 20f
            setTextColor(Color.rgb(89, 195, 195))
        }
        statusView = TextView(this).apply {
            setText(R.string.relay_status_stopped)
            textSize = 22f
            setTextColor(Color.WHITE)
            setPadding(0, padding / 2, 0, padding)
        }
        startButton = Button(this).apply {
            setText(R.string.relay_start)
            minHeight = (64 * resources.displayMetrics.density).toInt()
            isFocusable = true
            setOnClickListener { requestStart() }
        }
        stopButton = Button(this).apply {
            setText(R.string.relay_stop)
            minHeight = (64 * resources.displayMetrics.density).toInt()
            isFocusable = true
            setOnClickListener {
                preferences.edit().putBoolean(USER_ENABLED, false).apply()
                VehicleOperationGate.setSessionActive(this@MainActivity, false)
                stopRelayService()
                statusView.setText(R.string.relay_status_stopped)
            }
        }
        val buttonRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.START
            addView(startButton, weightedButtonParams())
            addView(stopButton, weightedButtonParams())
        }
        container.addView(
            title,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        container.addView(description)
        container.addView(modeView)
        container.addView(statusView)
        container.addView(buttonRow)
        startButton.requestFocus()
        return container
    }

    private fun weightedButtonParams() = LinearLayout.LayoutParams(
        0,
        ViewGroup.LayoutParams.WRAP_CONTENT,
        1f,
    ).apply {
        marginEnd = (12 * resources.displayMetrics.density).toInt()
    }

    private fun requestStart() {
        val capabilities = capabilityDetector.detect()
        renderCapabilities(capabilities)
        if (capabilities.mode == RelayMode.UNAVAILABLE) {
            statusView.setText(R.string.relay_mode_unavailable)
            return
        }
        if (!capabilities.bluetoothEnabled) {
            statusView.setText(R.string.error_bluetooth_off)
            return
        }
        val missing = requestedPermissions(capabilities.mode).filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            statusView.setText(R.string.relay_status_permission)
            requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
            return
        }
        beginRelay()
    }

    private fun beginRelay() {
        preferences.edit().putBoolean(USER_ENABLED, true).apply()
        if (BuildConfig.VEHICLE_GATED) {
            VehicleOperationGate.setSessionActive(this, true)
        }
        statusView.setText(R.string.relay_status_starting)
        startRelayService()
    }

    private fun startRelayService() {
        ContextCompat.startForegroundService(
            this,
            Intent(this, RelayForegroundService::class.java),
        )
    }

    private fun stopRelayService() {
        stopService(Intent(this, RelayForegroundService::class.java))
    }

    private fun renderCapabilities(capabilities: BleCapabilities) {
        modeView.setText(
            when (capabilities.mode) {
                RelayMode.DUAL_ROLE -> R.string.relay_mode_dual
                RelayMode.CENTRAL_ONLY -> R.string.relay_mode_central
                RelayMode.UNAVAILABLE -> R.string.relay_mode_unavailable
            },
        )
        startButton.isEnabled = capabilities.mode != RelayMode.UNAVAILABLE
    }

    private fun renderMeshEvent(event: Map<String, Any?>) {
        when (event["type"]) {
            "status", "snapshot" -> {
                val status = event["status"] as? String ?: return
                statusView.setText(
                    when (status) {
                        "starting" -> R.string.relay_status_starting
                        "active" -> R.string.relay_status_active
                        "degraded" -> R.string.relay_status_degraded
                        "vehicle_gated" -> R.string.relay_status_vehicle_gate
                        else -> R.string.relay_status_stopped
                    },
                )
            }
            "error" -> statusView.text = getString(
                R.string.relay_status_error,
                event["message"] as? String ?: getString(R.string.error_ble_start),
            )
        }
    }

    private fun hasMeshPermissions(mode: RelayMode): Boolean =
        requestedPermissions(mode)
            .filterNot { it == Manifest.permission.POST_NOTIFICATIONS }
            .all {
                ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
            }

    private fun requestedPermissions(mode: RelayMode): List<String> = buildList {
        add(Manifest.permission.BLUETOOTH_SCAN)
        add(Manifest.permission.BLUETOOTH_CONNECT)
        if (mode == RelayMode.DUAL_ROLE) {
            add(Manifest.permission.BLUETOOTH_ADVERTISE)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            add(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    private companion object {
        const val PERMISSION_REQUEST = 7411
        const val PREFERENCES = "relay_ui"
        const val USER_ENABLED = "user_enabled"
    }
}
