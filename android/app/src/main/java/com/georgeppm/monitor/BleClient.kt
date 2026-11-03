package com.georgeppm.monitor

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import java.util.UUID

/**
 * BLE central for the George PPM ESP32.
 *
 * Notes that matter on real phones (each one was a source of bugs in the field):
 *  - API 31+ needs BLUETOOTH_SCAN / BLUETOOTH_CONNECT runtime permissions;
 *    API <= 30 needs ACCESS_FINE_LOCATION to see scan results at all.
 *  - Always close() the previous BluetoothGatt. disconnect() alone leaks the
 *    client interface and the next connect silently returns null.
 *  - Notification delivery needs the CCCD descriptor written, not just
 *    setCharacteristicNotification().
 *  - API 33 changed the onCharacteristicChanged signature; both are handled.
 */
class BleClient(private val context: Context, private val listener: Listener) {

    interface Listener {
        fun onStatus(text: String)
        fun onTelemetry(t: Telemetry)
        fun onStateChanged(connected: Boolean, deviceLabel: String)
        /** Link metadata; called on connect, on MTU change and on each RSSI poll. */
        fun onMeta(mtu: Int, rssi: Int) {}
    }

    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("4a5b6c7d-0001-4d8e-9f00-a1b2c3d4e5f6")
        val TELEM_UUID: UUID = UUID.fromString("4a5b6c7d-0002-4d8e-9f00-a1b2c3d4e5f6")
        val CMD_UUID: UUID = UUID.fromString("4a5b6c7d-0003-4d8e-9f00-a1b2c3d4e5f6")
        private val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private const val TARGET_MTU = 247
        private const val SCAN_MS = 12000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private val adapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private var gatt: BluetoothGatt? = null
    private var telemChar: BluetoothGattCharacteristic? = null
    private var cmdChar: BluetoothGattCharacteristic? = null
    private var scanning = false
    private var discovered = false
    private var mtuValue = 0
    private var rssiValue = 0

    /** BluetoothGatt has no RSSI subscription, so it has to be polled. */
    private val rssiPoller = object : Runnable {
        @SuppressLint("MissingPermission")
        override fun run() {
            val g = gatt ?: return
            try {
                g.readRemoteRssi()
            } catch (e: SecurityException) {
                // ignore
            }
            handler.postDelayed(this, 5000)
        }
    }

    fun isBluetoothReady(): Boolean = adapter != null && adapter.isEnabled

    fun deviceName(): String? = try {
        adapter?.name
    } catch (e: SecurityException) {
        null
    }

    // ------------------------------------------------------------------ scan
    @SuppressLint("MissingPermission")
    fun startScan() {
        val a = adapter
        if (a == null || !a.isEnabled) {
            listener.onStatus("Bluetooth is off")
            return
        }
        val scanner = a.bluetoothLeScanner
        if (scanner == null) {
            listener.onStatus("BLE scanner unavailable")
            return
        }
        stopScan()
        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(SERVICE_UUID))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        scanning = true
        listener.onStatus("Scanning for GeorgePPM…")
        scanner.startScan(listOf(filter), settings, scanCallback)

        handler.postDelayed({
            if (scanning && gatt == null) {
                stopScan()
                listener.onStatus("No GeorgePPM found (is the ESP32 powered?)")
            }
        }, SCAN_MS)
    }

    @SuppressLint("MissingPermission")
    fun stopScan() {
        if (!scanning) return
        scanning = false
        try {
            adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (e: SecurityException) {
            // permission revoked mid-scan
        }
    }

    private val scanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device ?: return
            val label = try {
                device.name ?: "GeorgePPM"
            } catch (e: SecurityException) {
                "GeorgePPM"
            }
            stopScan()
            listener.onStatus("Found $label, connecting…")
            connect(device)
        }

        override fun onScanFailed(errorCode: Int) {
            scanning = false
            listener.onStatus("Scan failed (code $errorCode)")
        }
    }

    // --------------------------------------------------------------- connect
    @SuppressLint("MissingPermission")
    fun connect(device: BluetoothDevice) {
        closeGatt()
        discovered = false
        gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } else {
            device.connectGatt(context, false, gattCallback)
        }
        if (gatt == null) {
            listener.onStatus("connectGatt() returned null")
        }
    }

    @SuppressLint("MissingPermission")
    fun disconnect() {
        stopScan()
        try {
            gatt?.disconnect()
        } catch (e: SecurityException) {
            // ignore
        }
        closeGatt()
        listener.onStateChanged(false, "")
        listener.onStatus("Disconnected")
    }

    /** disconnect() frees the connection; close() frees the client interface. */
    @SuppressLint("MissingPermission")
    private fun closeGatt() {
        try {
            gatt?.close()
        } catch (e: Exception) {
            // ignore
        }
        gatt = null
        telemChar = null
        cmdChar = null
        mtuValue = 0
        handler.removeCallbacks(rssiPoller)
    }

    @SuppressLint("MissingPermission")
    fun resetTotal() = sendCommand("RESET")

    @SuppressLint("MissingPermission")
    fun sendCommand(cmd: String) {
        val g = gatt ?: return
        val c = cmdChar ?: return
        try {
            c.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                g.writeCharacteristic(c, cmd.toByteArray(), BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE)
            } else {
                @Suppress("DEPRECATION")
                c.value = cmd.toByteArray()
                @Suppress("DEPRECATION")
                g.writeCharacteristic(c)
            }
            listener.onStatus("Sent: $cmd")
        } catch (e: SecurityException) {
            listener.onStatus("Write denied")
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {

        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    val label = try {
                        g.device.name ?: "GeorgePPM"
                    } catch (e: SecurityException) {
                        "GeorgePPM"
                    }
                    listener.onStateChanged(true, label)
                    listener.onStatus("Connected — negotiating MTU…")
                    // 23-byte default MTU truncates our JSON, so ask for more first.
                    if (!g.requestMtu(TARGET_MTU)) {
                        g.discoverServices()
                    }
                    // Some stacks never deliver onMtuChanged: guarantee discovery.
                    handler.postDelayed({
                        val cur = gatt
                        if (cur === g && !discovered) cur.discoverServices()
                    }, 2500)
                    handler.post(rssiPoller)
                }

                BluetoothProfile.STATE_DISCONNECTED -> {
                    listener.onStateChanged(false, "")
                    listener.onStatus("Disconnected (status $status)")
                    closeGatt()
                }
            }
        }

        @SuppressLint("MissingPermission")
        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            mtuValue = mtu
            listener.onStatus("MTU = $mtu")
            listener.onMeta(mtuValue, rssiValue)
            if (!discovered) g.discoverServices()
        }

        override fun onReadRemoteRssi(g: BluetoothGatt, rssi: Int, status: Int) {
            rssiValue = rssi
            listener.onMeta(mtuValue, rssiValue)
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            discovered = true
            val service = g.getService(SERVICE_UUID)
            if (service == null) {
                listener.onStatus("Service not found on device")
                return
            }
            telemChar = service.getCharacteristic(TELEM_UUID)
            cmdChar = service.getCharacteristic(CMD_UUID)
            val t = telemChar
            if (t == null) {
                listener.onStatus("Telemetry characteristic missing")
                return
            }
            g.setCharacteristicNotification(t, true)
            val cccd = t.getDescriptor(CCCD_UUID)
            if (cccd != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                } else {
                    @Suppress("DEPRECATION")
                    cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    @Suppress("DEPRECATION")
                    g.writeDescriptor(cccd)
                }
            } else {
                listener.onStatus("Subscribed (no CCCD present)")
            }
        }

        override fun onDescriptorWrite(
            g: BluetoothGatt,
            descriptor: BluetoothGattDescriptor,
            status: Int
        ) {
            if (descriptor.uuid == CCCD_UUID) {
                listener.onStatus(if (status == BluetoothGatt.GATT_SUCCESS) "Subscribed ✓" else "Subscribe failed ($status)")
            }
        }

        // API 33+
        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            handleValue(characteristic, value)
        }

        // API < 33
        @Deprecated("Deprecated in API 33")
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(
            g: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic
        ) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            @Suppress("DEPRECATION")
            val v = characteristic.value ?: return
            handleValue(characteristic, v)
        }
    }

    private fun handleValue(c: BluetoothGattCharacteristic, value: ByteArray) {
        if (c.uuid != TELEM_UUID) return
        val text = String(value, Charsets.UTF_8)
        val t = Telemetry.parse(text)
        if (t != null) {
            listener.onTelemetry(t)
        } else {
            listener.onStatus("Bad frame: $text")
        }
    }
}
