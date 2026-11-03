package com.georgeppm.monitor

import android.os.Handler
import android.os.Looper
import kotlin.math.sin
import kotlin.random.Random

/**
 * Synthetic telemetry, so the whole UI can be exercised with no ESP32 present.
 *
 * Deliberately emits the same [Telemetry] objects the BLE client produces, with
 * believable dynamics: flow and RPM swing, the total only ever increases, and
 * every 20th frame drops the battery to null to prove the "sensor absent" path
 * renders correctly.
 */
class Simulator(private val listener: BleClient.Listener) {

    private val handler = Handler(Looper.getMainLooper())
    private var running = false
    private var tick = 0
    private var total = 0.0
    private val startedAt = System.currentTimeMillis()

    private val loop = object : Runnable {
        override fun run() {
            if (!running) return
            tick++

            val flow = 12.5 + 3.0 * sin(tick / 7.0)            // L/min
            total += flow / 60.0                                // litres per second
            val rpm = 1450.0 + 120.0 * sin(tick / 5.0)
            val amps = 2.1 + 0.35 * sin(tick / 4.0)
            val battery = if (tick % 20 == 0) null else 12.6 + 0.4 * sin(tick / 11.0)

            listener.onTelemetry(
                Telemetry(
                    flowLpm = flow,
                    totalL = total,
                    rpm = rpm.toInt(),
                    amps = amps,
                    battery = battery,
                    clients = 1,
                    uptimeMs = System.currentTimeMillis() - startedAt
                )
            )
            listener.onMeta(247, -54 + Random.nextInt(-4, 5))
            handler.postDelayed(this, 1000)
        }
    }

    fun isRunning(): Boolean = running

    fun start() {
        if (running) return
        running = true
        tick = 0
        total = 0.0
        listener.onStateChanged(true, "Simulation")
        listener.onStatus("Simulation mode — synthetic frames, no hardware")
        handler.post(loop)
    }

    fun stop() {
        running = false
        handler.removeCallbacksAndMessages(null)
        listener.onStateChanged(false, "")
        listener.onStatus("Simulation stopped")
    }

    fun resetTotal() {
        total = 0.0
        listener.onStatus("Total reset (simulated)")
    }
}
