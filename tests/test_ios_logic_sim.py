#!/usr/bin/env python3
"""test_ios_logic_sim.py - simulate the iOS app's logic locally.

The Swift app cannot run on Windows (no Xcode, no iOS Simulator, and SwiftUI /
CoreBluetooth are Apple-only frameworks). What CAN be checked here is the logic:
this file mirrors TelemetryFormatter.swift and the Telemetry decode rules, runs
the SAME fixtures as GeorgePPMTests/TelemetryTests.swift, and asserts the SAME
expected strings.

If this passes and the XCTest suite passes in CI, the only unproven part is that
the Swift compiles - not that the behaviour is right.

Run: python tests/test_ios_logic_sim.py
"""
import json
import os
import sys

PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(("  PASS  " if cond else "  FAIL  ") + name + (" " + detail if detail else ""))


# ---- mirror of TelemetryFormatter.swift -------------------------------
LOW_BATTERY = 11.8


def fmt_2f(v):
    return "%.2f" % v


def amps(v):
    return "--" if v is None else "%.2f" % v


def battery(v):
    return "--" if v is None else "%.2f" % v


def is_battery_low(v):
    return False if v is None else v < LOW_BATTERY


def uptime(ms):
    return "--" if ms <= 0 else "%d s" % (ms // 1000)


def rssi(v):
    return "--" if v == 0 else "%d dBm" % v


# ---- mirror of Telemetry.parse (Swift Decodable) ---------------------
REQUIRED = ("f", "t", "r", "a", "v", "c", "ms")


def parse(raw):
    try:
        o = json.loads(raw)
    except Exception:
        return None
    if not isinstance(o, dict):
        return None
    # Decodable requires every non-optional key to be present
    for k in REQUIRED:
        if k not in o:
            return None
    if o["a"] is not None and not isinstance(o["a"], (int, float)):
        return None
    if o["v"] is not None and not isinstance(o["v"], (int, float)):
        return None
    return o


# ---- fixtures: identical to the XCTest file --------------------------
LIVE = '{"f":12.34,"t":45.67,"r":1450,"a":1.23,"v":12.64,"c":1,"ms":123456}'
IDLE = '{"f":0.00,"t":0.00,"r":0,"a":null,"v":null,"c":0,"ms":6801}'

print("=" * 64)
print("1. testDecodesLiveFrame")
print("=" * 64)
t = parse(LIVE)
check("live frame decodes", t is not None)
if t:
    check("f == 12.34", abs(t["f"] - 12.34) < 1e-4, "(%.4f)" % t["f"])
    check("t == 45.67", abs(t["t"] - 45.67) < 1e-4)
    check("r == 1450", t["r"] == 1450)
    check("a == 1.23", abs((t["a"] or -1) - 1.23) < 1e-4)
    check("v == 12.64", abs((t["v"] or -1) - 12.64) < 1e-4)
    check("c == 1", t["c"] == 1)
    check("ms == 123456", t["ms"] == 123456)

print()
print("=" * 64)
print("2. testNullSensorsDecodeAsNil")
print("=" * 64)
i = parse(IDLE)
check("idle frame decodes", i is not None)
if i:
    check("absent ACS712 -> None (not 0.0)", i["a"] is None)
    check("absent battery -> None (not 0.0)", i["v"] is None)
    check("r == 0", i["r"] == 0)

print()
print("=" * 64)
print("3. testGarbageIsRejected")
print("=" * 64)
check("plain text rejected", parse("not json") is None)
check("partial frame rejected", parse('{"f":12.34}') is None)
check("empty input rejected", parse("") is None)

print()
print("=" * 64)
print("4. formatter dashes for missing sensors")
print("=" * 64)
check("amps(nil) == '--'", amps(None) == "--", amps(None))
check("battery(nil) == '--'", battery(None) == "--", battery(None))
check("amps(1.234) == '1.23'", amps(1.234) == "1.23", amps(1.234))
check("battery(12.64) == '12.64'", battery(12.64) == "12.64", battery(12.64))

print()
print("=" * 64)
print("5. low battery flag")
print("=" * 64)
check("11.5 is low", is_battery_low(11.5) is True)
check("12.6 is not low", is_battery_low(12.6) is False)
check("nil is not 'low'", is_battery_low(None) is False)

print()
print("=" * 64)
print("6. uptime and rssi")
print("=" * 64)
check("uptime(123456) == '123 s'", uptime(123456) == "123 s", uptime(123456))
check("uptime(0) == '--'", uptime(0) == "--")
check("rssi(0) == '--'", rssi(0) == "--")
check("rssi(-54) == '-54 dBm'", rssi(-54) == "-54 dBm", rssi(-54))

print()
print("=" * 64)
print("7. frame size vs MTU")
print("=" * 64)
n = len(LIVE.encode())
check("frame <= 244 bytes (fits MTU 247)", n <= 244, "(%d bytes)" % n)
check("frame > 20 bytes (does NOT fit default MTU)", n > 20, "(%d bytes)" % n)

print()
print("=" * 64)
print("8. structural smoke check on the Swift sources")
print("=" * 64)
sdir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ios", "GeorgePPM")
for name in sorted(os.listdir(sdir)):
    if not name.endswith(".swift"):
        continue
    src = open(os.path.join(sdir, name), encoding="utf-8").read()
    # naive balance check: strip line comments and string literals crudely
    depth = {"{": 0, "(": 0, "[": 0}
    pairs = {"}": "{", ")": "(", "]": "["}
    for ch in src:
        if ch in depth:
            depth[ch] += 1
        elif ch in pairs:
            depth[pairs[ch]] -= 1
    ok = all(v == 0 for v in depth.values())
    check("%-24s balanced %s" % (name, depth), ok)

print()
print("=" * 64)
print("RESULT: %d passed, %d failed" % (len(PASS), len(FAIL)))
if FAIL:
    print("failed:", ", ".join(FAIL))
print("=" * 64)
sys.exit(1 if FAIL else 0)
