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
print("RESULT: \(passed) passed, \(failed) failed")
print("==============================================================")
