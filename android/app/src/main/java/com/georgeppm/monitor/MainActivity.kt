package com.georgeppm.monitor

import android.Manifest
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.os.Build
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.button.MaterialButton
import com.google.android.material.chip.Chip
import com.google.android.material.materialswitch.MaterialSwitch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * George PPM Monitor.
 *
 * Two data sources feed the same UI:
 *   - [BleClient]  real ESP32 over BLE
 *   - [Simulator]  synthetic frames, toggled by the Simulation switch
 *
 * Permission model differs by API level, so both paths live here:
 *   API 31+  BLUETOOTH_SCAN + BLUETOOTH_CONNECT (runtime)
 *   API <=30 BLUETOOTH + BLUETOOTH_ADMIN (install-time) + ACCESS_FINE_LOCATION (runtime)
 */
class MainActivity : AppCompatActivity(), BleClient.Listener {

    private lateinit var statusChip: Chip
    private lateinit var debitValue: TextView
    private lateinit var totalValue: TextView
    private lateinit var rpmValue: TextView
    private lateinit var currentValue: TextView
    private lateinit var batteryValue: TextView
    private lateinit var metaText: TextView
    private lateinit var logText: TextView
    private lateinit var logScroll: ScrollView
    private lateinit var scanButton: MaterialButton
    private lateinit var resetButton: MaterialButton
    private lateinit var simSwitch: MaterialSwitch

    private lateinit var ble: BleClient
    private lateinit var simulator: Simulator

    private val logLines = ArrayDeque<String>()
    private val stamp = SimpleDateFormat("HH:mm:ss", Locale.US)

    private var connected = false
    private var deviceLabel = ""
    private var mtu = 0
    private var rssi = 0
    private var uptimeMs = 0L
    private var clients = 0

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { result ->
        if (result.values.all { it }) {
            beginScan()
        } else {
            setStatus("Bluetooth permission denied", R.color.bad)
            log("Permission denied")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        statusChip = findViewById(R.id.statusChip)
        debitValue = findViewById(R.id.debitValue)
        totalValue = findViewById(R.id.totalValue)
        rpmValue = findViewById(R.id.rpmValue)
        currentValue = findViewById(R.id.currentValue)
        batteryValue = findViewById(R.id.batteryValue)
        metaText = findViewById(R.id.metaText)
        logText = findViewById(R.id.logText)
        logScroll = findViewById(R.id.logScroll)
        scanButton = findViewById(R.id.scanButton)
        resetButton = findViewById(R.id.resetButton)
        simSwitch = findViewById(R.id.simSwitch)

        ble = BleClient(this, this)
        simulator = Simulator(this)

        scanButton.setOnClickListener {
            if (connected) {
                ble.disconnect()
            } else {
                val missing = missingPermissions()
                if (missing.isNotEmpty()) permissionLauncher.launch(missing) else beginScan()
            }
        }

        resetButton.setOnClickListener {
            if (simulator.isRunning()) simulator.resetTotal() else ble.resetTotal()
        }

        simSwitch.setOnCheckedChangeListener { _, checked ->
            if (checked) {
                ble.disconnect()
                simulator.start()
            } else {
                simulator.stop()
            }
        }

        renderMeta()
        log("Ready")
    }

    override fun onDestroy() {
        super.onDestroy()
        if (simulator.isRunning()) simulator.stop()
        ble.disconnect()
    }

    // ------------------------------------------------------------ permissions
    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
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
            setStatus("Bluetooth is off", R.color.bad)
            log("Enable Bluetooth and retry")
            return
        }
        setStatus("Scanning…", R.color.warn)
        ble.startScan()
    }

    // -------------------------------------------------------------- callbacks
    override fun onStatus(text: String) {
        runOnUiThread { log(text) }
    }

    override fun onTelemetry(t: Telemetry) {
        runOnUiThread {
            uptimeMs = t.uptimeMs
            clients = t.clients

            debitValue.text = String.format(Locale.US, "%.2f", t.flowLpm)
            totalValue.text = String.format(Locale.US, "%.2f", t.totalL)
            rpmValue.text = String.format(Locale.US, "%d", t.rpm)

            // null means "sensor not detected" — show dashes, never a fake 0.00
            if (t.amps != null) {
                currentValue.text = String.format(Locale.US, "%.2f", t.amps)
                currentValue.setTextColor(ContextCompat.getColor(this, R.color.textPrimary))
            } else {
                currentValue.text = "--"
                currentValue.setTextColor(ContextCompat.getColor(this, R.color.textMuted))
            }

            if (t.battery != null) {
                batteryValue.text = String.format(Locale.US, "%.2f", t.battery)
                val low = t.battery < 11.8
                batteryValue.setTextColor(
                    ContextCompat.getColor(this, if (low) R.color.bad else R.color.textPrimary)
                )
            } else {
                batteryValue.text = "--"
                batteryValue.setTextColor(ContextCompat.getColor(this, R.color.textMuted))
            }

            renderMeta()
        }
    }

    override fun onStateChanged(connected: Boolean, deviceLabel: String) {
        runOnUiThread {
            this.connected = connected
            this.deviceLabel = deviceLabel
            scanButton.text = if (connected) "Disconnect" else "Scan & Connect"
            if (connected) {
                setStatus("Connected · " + deviceLabel, R.color.good)
            } else {
                setStatus("Idle", R.color.surfaceHigh)
                mtu = 0
                rssi = 0
                uptimeMs = 0
                clients = 0
            }
            renderMeta()
        }
    }

    override fun onMeta(mtu: Int, rssi: Int) {
        runOnUiThread {
            this.mtu = mtu
            this.rssi = rssi
            renderMeta()
        }
    }

    // ------------------------------------------------------------------ views
    private fun renderMeta() {
        val dev = if (deviceLabel.isEmpty()) "--" else deviceLabel
        val mtuText = if (mtu > 0) mtu.toString() else "--"
        val rssiText = if (rssi != 0) (rssi.toString() + " dBm") else "--"
        val up = if (uptimeMs > 0) ((uptimeMs / 1000).toString() + " s") else "--"
        metaText.text = String.format(
            Locale.US,
            "device   %s%nlink     %s%nmtu      %s%nuptime   %s%nclients  %d",
            dev,
            rssiText,
            mtuText,
            up,
            clients
        )
    }

    private fun setStatus(text: String, colorRes: Int) {
        statusChip.text = text
        statusChip.chipBackgroundColor =
            ColorStateList.valueOf(ContextCompat.getColor(this, colorRes))
    }

    private fun log(line: String) {
        logLines.addLast(stamp.format(Date()) + "  " + line)
        while (logLines.size > 60) logLines.removeFirst()
        logText.text = logLines.joinToString("\n")
        logScroll.post { logScroll.fullScroll(ScrollView.FOCUS_DOWN) }
    }
}
