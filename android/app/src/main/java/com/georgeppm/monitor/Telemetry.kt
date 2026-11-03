package com.georgeppm.monitor

import org.json.JSONObject

/**
 * One telemetry frame from the ESP32.
 *
 * Wire format (ASCII JSON, published on the notify characteristic):
 *   {"f":12.34,"t":45.67,"r":1450,"a":1.23,"v":12.64,"c":1,"ms":123456}
 *
 *   f  = flow, litres per minute
 *   t  = total volume, litres
 *   r  = RPM
 *   a  = current, amps — null when the ACS712 is not detected
 *   v  = battery volts — null when the divider is not fitted
 *   c  = number of connected BLE clients
 *   ms = ESP32 uptime in milliseconds
 *
 * a and v are nullable on purpose: a flat 0.00 A would be indistinguishable
 * from a genuinely idle load, which is exactly the wrong thing to show.
 */
data class Telemetry(
    val flowLpm: Double,
    val totalL: Double,
    val rpm: Int,
    val amps: Double?,
    val battery: Double?,
    val clients: Int,
    val uptimeMs: Long
) {
    companion object {
        fun parse(raw: String): Telemetry? = try {
            val o = JSONObject(raw)
            Telemetry(
                flowLpm = o.optDouble("f", 0.0),
                totalL = o.optDouble("t", 0.0),
                rpm = o.optInt("r", 0),
                amps = if (o.isNull("a")) null else o.optDouble("a", 0.0),
                battery = if (o.isNull("v")) null else o.optDouble("v", 0.0),
                clients = o.optInt("c", 0),
                uptimeMs = o.optLong("ms", 0L)
            )
        } catch (e: Exception) {
            null
        }
    }
}
