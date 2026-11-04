// main.swift - run the iOS app's Foundation-only logic on a real Swift compiler.
//
// Telemetry.swift and TelemetryFormatter.swift import only Foundation, so unlike
// the SwiftUI / CoreBluetooth files they can be compiled and EXECUTED on Windows.
// This harness runs the same assertions as GeorgePPMTests/TelemetryTests.swift
// (minus XCTest, which needs SPM on Windows) against frames captured from the
// actual ESP32.
//
// Build:
//   call "<VS>\vcvars64.bat"
//   swiftc Telemetry.swift TelemetryFormatter.swift main.swift -o harness.exe
import Foundation

var passed = 0
var failed = 0

func check(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond {
        passed += 1
        print("  PASS  \(name) \(detail)")
    } else {
        failed += 1
        print("  FAIL  \(name) \(detail)")
    }
}

// ---- fixtures: identical to the XCTest file and the Python simulation ----
let liveFrame = #"{"f":12.34,"t":45.67,"r":1450,"a":1.23,"v":12.64,"c":1,"ms":123456}"#
let idleFrame = #"{"f":0.00,"t":0.00,"r":0,"a":null,"v":null,"c":0,"ms":6801}"#

print("==============================================================")
print("1. decode a live frame")
print("==============================================================")
if let t = Telemetry.parse(Data(liveFrame.utf8)) {
    check("live frame decodes", true)
    check("f == 12.34", abs(t.f - 12.34) < 1e-4, String(format: "(%.4f)", t.f))
    check("t == 45.67", abs(t.t - 45.67) < 1e-4)
    check("r == 1450", t.r == 1450, String(t.r))
    check("a == 1.23", abs((t.a ?? -1) - 1.23) < 1e-4)
    check("v == 12.64", abs((t.v ?? -1) - 12.64) < 1e-4)
    check("c == 1", t.c == 1)
    check("ms == 123456", t.ms == 123456)
} else {
    check("live frame decodes", false, "returned nil")
}

print("")
print("==============================================================")
print("2. null sensors decode as nil, never 0.0")
print("==============================================================")
if let t = Telemetry.parse(Data(idleFrame.utf8)) {
    check("idle frame decodes", true)
    check("absent ACS712 -> nil", t.a == nil)
    check("absent battery -> nil", t.v == nil)
    check("r == 0", t.r == 0)
} else {
    check("idle frame decodes", false)
}

print("")
print("==============================================================")
print("3. garbage is rejected")
print("==============================================================")
check("plain text rejected", Telemetry.parse(Data("not json".utf8)) == nil)
check("partial frame rejected", Telemetry.parse(Data(#"{"f":12.34}"#.utf8)) == nil)
check("empty input rejected", Telemetry.parse(Data()) == nil)

print("")
print("==============================================================")
print("4. formatter")
print("==============================================================")
check("amps(nil) == \"--\"", TelemetryFormatter.amps(nil) == "--", TelemetryFormatter.amps(nil))
check("battery(nil) == \"--\"", TelemetryFormatter.battery(nil) == "--")
check("amps(1.234) == \"1.23\"", TelemetryFormatter.amps(1.234) == "1.23", TelemetryFormatter.amps(1.234))
check("battery(12.64) == \"12.64\"", TelemetryFormatter.battery(12.64) == "12.64")
check("11.5 is low", TelemetryFormatter.isBatteryLow(11.5))
check("12.6 is not low", !TelemetryFormatter.isBatteryLow(12.6))
check("nil is not low", !TelemetryFormatter.isBatteryLow(nil))
check("uptime(123456) == \"123 s\"", TelemetryFormatter.uptime(123456) == "123 s", TelemetryFormatter.uptime(123456))
check("uptime(0) == \"--\"", TelemetryFormatter.uptime(0) == "--")
check("rssi(0) == \"--\"", TelemetryFormatter.rssi(0) == "--")
check("rssi(-54) == \"-54 dBm\"", TelemetryFormatter.rssi(-54) == "-54 dBm", TelemetryFormatter.rssi(-54))
check("flow(12.344) == \"12.34\"", TelemetryFormatter.flow(12.344) == "12.34")
check("total(0) == \"0.00\"", TelemetryFormatter.total(0) == "0.00")
check("rpm(1450) == \"1450\"", TelemetryFormatter.rpm(1450) == "1450")
check("clients(3) == \"3\"", TelemetryFormatter.clients(3) == "3")

print("")
print("==============================================================")
print("5. frame size vs MTU")
print("==============================================================")
let n = liveFrame.utf8.count
check("frame <= 244 bytes (fits MTU 247)", n <= 244, "(\(n) bytes)")
check("frame > 20 bytes (does not fit default MTU)", n > 20, "(\(n) bytes)")

print("")
print("==============================================================")
print("6. BLE contract (must match firmware/ble_link.py)")
print("==============================================================")
check("service UUID well formed", BleSpec.isWellFormed(BleSpec.serviceUUID), BleSpec.serviceUUID)
check("telemetry UUID well formed", BleSpec.isWellFormed(BleSpec.telemetryUUID))
check("command UUID well formed", BleSpec.isWellFormed(BleSpec.commandUUID))
check("UUIDs are 36 chars", BleSpec.serviceUUID.count == 36 && BleSpec.telemetryUUID.count == 36)
check("device name is GeorgePPM", BleSpec.deviceName == "GeorgePPM")
check("commands are RESET and ZERO", BleSpec.commandReset == "RESET" && BleSpec.commandZero == "ZERO")
check("target MTU exceeds frame size", BleSpec.targetMTU > 67, String(BleSpec.targetMTU))
check("malformed UUID rejected", !BleSpec.isWellFormed("4a5b6c7d-0001-4d8e-9f00"))
check("non-hex UUID rejected", !BleSpec.isWellFormed("zzzzzzzz-0001-4d8e-9f00-a1b2c3d4e5f6"))

print("")
print("==============================================================")
print("7. synthetic telemetry generator")
print("==============================================================")
var gen = SyntheticTelemetry()
var prevTotal = 0.0
var monotonic = true
var rpmInRange = true
var batteryNils = 0
for i in 1...40 {
    let f = gen.next(uptimeMs: Int64(i * 1000))
    if f.t < prevTotal { monotonic = false }
    prevTotal = f.t
    if f.r < 1300 || f.r > 1600 { rpmInRange = false }
    if f.v == nil { batteryNils += 1 }
}
check("total only ever increases", monotonic)
check("rpm stays believable (1300-1600)", rpmInRange)
check("battery drops to nil every 20th frame", batteryNils == 2, "(\(batteryNils))")
check("40 frames advanced the tick", gen.tick == 40, String(gen.tick))
gen.resetTotal()
check("resetTotal zeroes the total", gen.total == 0.0)

print("")
print("==============================================================")
print("8. LinkState")
print("==============================================================")
check("connected reports connected", LinkState.connected("GeorgePPM").isConnected)
check("idle reports not connected", !LinkState.idle.isConnected)
check("failed reports not connected", !LinkState.failed("x").isConnected)
check("label carries the device name", LinkState.connected("GeorgePPM").label.contains("GeorgePPM"), LinkState.connected("GeorgePPM").label)
check("equal states compare equal", LinkState.scanning == LinkState.scanning)
check("different states differ", LinkState.idle != LinkState.bluetoothOff)

print("")
print("==============================================================")
print("9. Dashboard view model")
print("==============================================================")
let live = Telemetry.parse(Data(liveFrame.utf8))
let d1 = Dashboard.make(frame: live, simulate: false, state: .connected("GeorgePPM"), rssi: -54)
check("flow text", d1.flow == "12.34", d1.flow)
check("total text", d1.total == "45.67")
check("rpm text", d1.rpm == "1450")
check("amps text", d1.amps == "1.23")
check("battery text", d1.battery == "12.64")
check("amps not flagged missing", !d1.ampsMissing)
check("battery not flagged missing", !d1.batteryMissing)
check("status label carries the device name", d1.statusLabel.contains("GeorgePPM"), d1.statusLabel)
check("connected -> ok status", d1.statusKind == .ok)
check("link row says connected", d1.linkRow == "BLE connected", d1.linkRow)
check("rssi row formatted", d1.rssiRow == "-54 dBm", d1.rssiRow)
check("mtu row is iOS auto", d1.mtuRow == "auto by iOS")
check("uptime row", d1.uptimeRow == "123 s", d1.uptimeRow)
check("clients row", d1.clientsRow == "1", d1.clientsRow)

let idle = Telemetry.parse(Data(idleFrame.utf8))
let d2 = Dashboard.make(frame: idle, simulate: false, state: .idle, rssi: 0)
check("absent amps renders -- and is flagged", d2.amps == "--" && d2.ampsMissing)
check("absent battery renders -- and is flagged", d2.battery == "--" && d2.batteryMissing)
check("idle status label", d2.statusLabel == "Idle", d2.statusLabel)
check("idle status kind", d2.statusKind == .idle)
check("rssi 0 renders --", d2.rssiRow == "--")
check("not connected link row", d2.linkRow == "--")

let d3 = Dashboard.make(frame: nil, simulate: true, state: .idle, rssi: 0)
check("simulate label", d3.statusLabel == "Simulation")
check("simulate rssi", d3.rssiRow == "-54 dBm")
check("simulate mtu", d3.mtuRow == "247 (sim)")
check("simulate link", d3.linkRow == "simulated")

let d4 = Dashboard.make(frame: nil, simulate: false, state: .scanning, rssi: 0)
check("nil frame renders dashes", d4.flow == "--" && d4.total == "--" && d4.rpm == "--")
check("scanning is a warning status", d4.statusKind == .warn)

let lowFrame = #"{"f":1.00,"t":1.00,"r":100,"a":0.50,"v":11.50,"c":0,"ms":5000}"#
let d5 = Dashboard.make(frame: Telemetry.parse(Data(lowFrame.utf8)), simulate: false, state: .failed("boom"), rssi: 0)
check("low battery flagged", d5.batteryLow, d5.battery)
check("failure status is bad", d5.statusKind == .bad)
check("failure label mentions the reason", d5.statusLabel.contains("boom"), d5.statusLabel)

print("")
print("==============================================================")
print("RESULT: \(passed) passed, \(failed) failed")
print("==============================================================")
