package com.georgeppm.monitor

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat

/**
 * George PPM Monitor — reads live telemetry from the ESP32 over BLE.
 *
 * Permission model differs by API level, so both paths are handled here:
 *   API 31+  BLUETOOTH_SCAN + BLUETOOTH_CONNECT (runtime)
 *   API <=30 BLUETOOTH + BLUETOOTH_ADMIN (install-time) + ACCESS_FINE_LOCATION (runtime)
 */
class MainActivity : AppCompatActivity(), BleClient.Listener {

    private lateinit var statusText: TextView
    private lateinit var debitValue: TextView
    private lateinit var totalValue: TextView
    private lateinit var rpmValue: TextView
    private lateinit var currentValue: TextView
    private lateinit var batteryValue: TextView
    private lateinit var bleCount: TextView
    private lateinit var logText: TextView
    private lateinit var scanButton: Button
    private lateinit var disconnectButton: Button

    private lateinit var ble: BleClient
    private val logLines = ArrayDeque<String>()

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { result ->
        if (result.values.all { it }) {
            beginScan()
        } else {
            statusText.text = "Bluetooth permission denied"
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        statusText = findViewById(R.id.statusText)
        debitValue = findViewById(R.id.debitValue)
        totalValue = findViewById(R.id.totalValue)
        rpmValue = findViewById(R.id.rpmValue)
        currentValue = findViewById(R.id.currentValue)
        batteryValue = findViewById(R.id.batteryValue)
        bleCount = findViewById(R.id.bleCount)
        logText = findViewById(R.id.logText)
        scanButton = findViewById(R.id.scanButton)
        disconnectButton = findViewById(R.id.disconnectButton)

        ble = BleClient(this, this)

        scanButton.setOnClickListener {
            val missing = missingPermissions()
            if (missing.isNotEmpty()) {
                permissionLauncher.launch(missing)
            } else {
                beginScan()
            }
        }

        disconnectButton.setOnClickListener {
            ble.disconnect()
            disconnectButton.isEnabled = false
            scanButton.isEnabled = true
            resetValues()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        ble.disconnect()
    }

    // ------------------------------------------------------------ permissions
    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT
            )
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun missingPermissions(): Array<String> =
        requiredPermissions().filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }.toTypedArray()

    // ------------------------------------------------------------------- scan
    private fun beginScan() {
        if (!ble.isBluetoothReady()) {
            statusText.text = "Bluetooth is off — enable it and retry"
            return
        }
        statusText.text = "Scanning…"
        scanButton.isEnabled = false
        disconnectButton.isEnabled = true
        ble.startScan()
    }

    // -------------------------------------------------------------- callbacks
    override fun onStatus(text: String) {
        runOnUiThread {
            statusText.text = text
            logLines.addLast(text)
            while (logLines.size > 40) logLines.removeFirst()
            logText.text = logLines.joinToString("\n")
        }
    }

    override fun onTelemetry(t: Telemetry) {
        runOnUiThread {
            debitValue.text = String.format("Debit  %.2f L/m", t.flowLpm)
            totalValue.text = String.format("Total  %.2f L", t.totalL)
            rpmValue.text = String.format("RPM  %d", t.rpm)
            currentValue.text = String.format("Arus  %.2f A", t.amps)
            batteryValue.text = if (t.battery != null) {
                String.format("Baterai  %.2f V", t.battery)
            } else {
                "Baterai  -- V (no sensor)"
            }
            // String.format instead of a Kotlin template, to keep this file
            // copy-pasteable through generators that eat dollar-brace sequences.
            bleCount.text = String.format(
                "BLE clients: %d   uptime: %d s",
                t.clients,
                t.uptimeMs / 1000
            )
        }
    }

    override fun onStateChanged(connected: Boolean, deviceLabel: String) {
        runOnUiThread {
            scanButton.isEnabled = !connected
            disconnectButton.isEnabled = connected
            if (connected) statusText.text = "Connected to " + deviceLabel
        }
    }

    private fun resetValues() {
        debitValue.text = "Debit  -- L/m"
        totalValue.text = "Total  -- L"
        rpmValue.text = "RPM  --"
        currentValue.text = "Arus  -- A"
        batteryValue.text = "Baterai  -- V"
        bleCount.text = "BLE clients: 0"
    }
}
