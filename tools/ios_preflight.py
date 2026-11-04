#!/usr/bin/env python3
"""ios_preflight.py - validate the iOS project without a Mac.

Catches the mistakes that would otherwise only appear 20 minutes into a CI run:
missing source files, a scheme that does not exist, required Info.plist keys,
tests referencing symbols that are not defined, unbalanced Swift braces, and
workflow paths that do not line up with the XcodeGen spec.

Run: python tools/ios_preflight.py
"""
import os
import re
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
IOS = os.path.normpath(os.path.join(HERE, "..", "ios"))
REPO = os.path.normpath(os.path.join(HERE, ".."))

PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(("  PASS  " if cond else "  FAIL  ") + name + (" " + detail if detail else ""))


def read(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


print("=" * 66)
print("1. XcodeGen spec")
print("=" * 66)
proj_path = os.path.join(IOS, "project.yml")
check("project.yml exists", os.path.exists(proj_path))
proj = yaml.safe_load(read(proj_path))
targets = proj.get("targets", {})
schemes = proj.get("schemes", {})
check("app target defined", "GeorgePPM" in targets)
check("test target defined", "GeorgePPMTests" in targets)
check("scheme defined", "GeorgePPM" in schemes)
if "GeorgePPM" in schemes:
    tt = schemes["GeorgePPM"].get("test", {}).get("targets", [])
    check("scheme runs the test target", "GeorgePPMTests" in tt, str(tt))
check("test target depends on the app",
      any(d.get("target") == "GeorgePPM" for d in targets.get("GeorgePPMTests", {}).get("dependencies", [])))

print()
print("=" * 66)
print("2. sources present")
print("=" * 66)
app_dir = os.path.join(IOS, "GeorgePPM")
test_dir = os.path.join(IOS, "GeorgePPMTests")
check("GeorgePPM/ exists", os.path.isdir(app_dir))
check("GeorgePPMTests/ exists", os.path.isdir(test_dir))
app_swift = sorted(f for f in os.listdir(app_dir) if f.endswith(".swift")) if os.path.isdir(app_dir) else []
test_swift = sorted(f for f in os.listdir(test_dir) if f.endswith(".swift")) if os.path.isdir(test_dir) else []
print("    app sources :", ", ".join(app_swift))
print("    test sources:", ", ".join(test_swift))
check("app has sources", len(app_swift) >= 5)
check("test target has sources", len(test_swift) >= 1)

print()
print("=" * 66)
print("3. required Info.plist keys (Bluetooth)")
print("=" * 66)
props = targets.get("GeorgePPM", {}).get("info", {}).get("properties", {})
check("NSBluetoothAlwaysUsageDescription present", "NSBluetoothAlwaysUsageDescription" in props)
check("NSBluetoothPeripheralUsageDescription present", "NSBluetoothPeripheralUsageDescription" in props)
check("UIRequiredDeviceCapabilities includes bluetooth-le",
      "bluetooth-le" in (props.get("UIRequiredDeviceCapabilities") or []))
check("bundle id set", targets.get("GeorgePPM", {}).get("settings", {}).get("base", {}).get("PRODUCT_BUNDLE_IDENTIFIER") is not None)

print()
print("=" * 66)
print("4. tests reference symbols that actually exist")
print("=" * 66)
app_src = "\n".join(read(os.path.join(app_dir, f)) for f in app_swift)
test_src = "\n".join(read(os.path.join(test_dir, f)) for f in test_swift)

for sym in ("Telemetry", "TelemetryFormatter", "BleSpec", "LinkState", "SyntheticTelemetry",
            "Dashboard", "BleCentral", "Simulator", "ContentView"):
    check("defined in app sources: " + sym,
          re.search(r"(struct|class|enum|final class)\s+" + sym + r"\b", app_src) is not None)

fmt_src = read(os.path.join(app_dir, "TelemetryFormatter.swift")) if os.path.exists(os.path.join(app_dir, "TelemetryFormatter.swift")) else ""
called = sorted(set(re.findall(r"TelemetryFormatter\.(\w+)", test_src)))
print("    formatter API used by tests:", ", ".join(called))
for fn in called:
    check("TelemetryFormatter.%s exists" % fn, re.search(r"static func " + fn + r"\b", fmt_src) is not None)

print()
print("=" * 66)
print("5. Swift structural smoke check")
print("=" * 66)
for f in app_swift + test_swift:
    path = os.path.join(app_dir if f in app_swift else test_dir, f)
    src = read(path)
    depth = {"{": 0, "(": 0, "[": 0}
    pairs = {"}": "{", ")": "(", "]": "["}
    for ch in src:
        if ch in depth:
            depth[ch] += 1
        elif ch in pairs:
            depth[pairs[ch]] -= 1
    check("%-26s balanced" % f, all(v == 0 for v in depth.values()), str(depth) if any(depth.values()) else "")

print()
print("=" * 66)
print("6. CoreBluetooth delegate selectors")
print("=" * 66)
# Signatures taken from Apple's documentation JSON on 2026-11-04:
#   https://developer.apple.com/tutorials/data/documentation/corebluetooth/
#       cbcentralmanagerdelegate.json
#       cbperipheraldelegate.json
# In Swift these are @objc optional protocol methods: a WRONG signature still
# compiles and simply never gets called. Only the argument labels matter for
# dispatch, so those are what we compare.
EXPECTED_SELECTORS = {
    "centralManagerDidUpdateState": "_:",
    "centralManager": "_:didDiscover:advertisementData:rssi:",
    "centralManager#connect": "_:didConnect:",
    "centralManager#failconnect": "_:didFailToConnect:error:",
    "centralManager#disconnect": "_:didDisconnectPeripheral:error:",
    "peripheral": "_:didDiscoverServices:",
    "peripheral#chars": "_:didDiscoverCharacteristicsFor:error:",
    "peripheral#notifstate": "_:didUpdateNotificationStateFor:error:",
    "peripheral#value": "_:didUpdateValueFor:error:",
    "peripheral#rssi": "_:didReadRSSI:error:",
}


def selectors_in(src):
    """Extract (funcName, argLabelChain) for every func in the source."""
    out = []
    for m in re.finditer(r"func\s+(\w+)\s*\(", src):
        name = m.group(1)
        # walk forward to the matching close paren
        i = m.end() - 1
        depth = 0
        params = ""
        while i < len(src):
            ch = src[i]
            if ch == "(":
                depth += 1
                if depth == 1:
                    i += 1
                    continue
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    break
            if depth >= 1:
                params += ch
            i += 1
        # split top-level commas
        parts, depth, cur = [], 0, ""
        for ch in params:
            if ch in "([<":
                depth += 1
            elif ch in ")]>":
                depth -= 1
            if ch == "," and depth == 0:
                parts.append(cur)
                cur = ""
            else:
                cur += ch
        if cur.strip():
            parts.append(cur)
        labels = []
        for p in parts:
            p = p.strip()
            if not p:
                continue
            head = p.split(":")[0].strip()
            tok = head.split()
            # "label name" -> label; "name" alone -> name is the label;
            # "_ name" -> the label is "_"
            labels.append(tok[0] if tok else "_")
        # Swift selector form: name(_:second:) -> "_:second:"
        out.append((name, "_:" + ":".join(labels[1:]) + ":" if len(labels) > 1
                    else "_:"))
    return out


found = selectors_in(app_src)
byname = {}
for n, sel in found:
    byname.setdefault(n, []).append(sel)

for label, want in EXPECTED_SELECTORS.items():
    fname = label.split("#")[0]
    have = byname.get(fname, [])
    ok = want in have
    check("%-24s %s" % (fname, want), ok, "" if ok else ("found " + str(have)))
    if ok:
        # keep one match consumed so duplicate names do not all pass on one entry
        have.remove(want)

print()
print("=" * 66)
print("7. BLE contract: firmware <-> iOS <-> Android")
print("=" * 66)
# Three separate codebases must agree on these strings. A drift compiles
# perfectly and simply never connects, so it is checked mechanically.

fw_path = os.path.join(REPO, "firmware", "ble_link.py")
fw_src = read(fw_path) if os.path.exists(fw_path) else ""
fw = {
    "service": (re.search(r'SERVICE_UUID\s*=\s*bluetooth\.UUID\("([^"]+)"\)', fw_src) or [None, ""])[1],
    "telemetry": (re.search(r'TELEM_UUID\s*=\s*bluetooth\.UUID\("([^"]+)"\)', fw_src) or [None, ""])[1],
    "command": (re.search(r'CMD_UUID\s*=\s*bluetooth\.UUID\("([^"]+)"\)', fw_src) or [None, ""])[1],
    "name": (re.search(r'_NAME\s*=\s*"([^"]+)"', fw_src) or [None, ""])[1],
}

kt_path = os.path.join(REPO, "android", "app", "src", "main", "java", "com", "georgeppm", "monitor", "BleClient.kt")
kt_src = read(kt_path) if os.path.exists(kt_path) else ""
kt = {
    "service": (re.search(r'SERVICE_UUID:\s*UUID\s*=\s*UUID\.fromString\("([^"]+)"\)', kt_src) or [None, ""])[1],
    "telemetry": (re.search(r'TELEM_UUID:\s*UUID\s*=\s*UUID\.fromString\("([^"]+)"\)', kt_src) or [None, ""])[1],
    "command": (re.search(r'CMD_UUID:\s*UUID\s*=\s*UUID\.fromString\("([^"]+)"\)', kt_src) or [None, ""])[1],
}

spec_src = read(os.path.join(app_dir, "BleSpec.swift"))
sw = {
    "service": (re.search(r'static let serviceUUID\s*=\s*"([^"]+)"', spec_src) or [None, ""])[1],
    "telemetry": (re.search(r'static let telemetryUUID\s*=\s*"([^"]+)"', spec_src) or [None, ""])[1],
    "command": (re.search(r'static let commandUUID\s*=\s*"([^"]+)"', spec_src) or [None, ""])[1],
    "name": (re.search(r'static let deviceName\s*=\s*"([^"]+)"', spec_src) or [None, ""])[1],
}

for key in ("service", "telemetry", "command"):
    check("firmware defines %s UUID" % key, bool(fw[key]), fw[key])
    check("android matches firmware (%s)" % key, kt[key] == fw[key] and bool(fw[key]), kt[key])
    check("iOS matches firmware (%s)" % key, sw[key] == fw[key] and bool(fw[key]), sw[key])
check("device name agrees (firmware vs iOS)", fw["name"] == sw["name"] and bool(fw["name"]), fw["name"])

print()
print("=" * 66)
print("8. CI workflow matches the project")
print("=" * 66)
wf_path = os.path.join(REPO, ".github", "workflows", "ios.yml")
check("workflow exists", os.path.exists(wf_path))
wf = yaml.safe_load(read(wf_path))
job = wf["jobs"]["build"]
wd = job.get("defaults", {}).get("run", {}).get("working-directory")
check("working-directory is ios", wd == "ios", str(wd))
body = read(wf_path)
check("generates project with xcodegen", "xcodegen generate" in body)
check("uses the GeorgePPM scheme", "-scheme GeorgePPM" in body)
check("picks a simulator dynamically", "SIM_NAME" in body)
check("no hardcoded simulator device", "name=iPhone 15" not in body.replace('"iPhone 15"', ""))
check("runs tests", "xcodebuild test" in body)
check("builds an unsigned ipa", "CODE_SIGNING_ALLOWED=NO" in body and ".ipa" in body)

print()
print("=" * 66)
print("RESULT: %d passed, %d failed" % (len(PASS), len(FAIL)))
if FAIL:
    print("failed:", ", ".join(FAIL))
print("=" * 66)
sys.exit(1 if FAIL else 0)
