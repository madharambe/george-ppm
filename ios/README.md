# George PPM Monitor — iOS app

SwiftUI + CoreBluetooth client for the same ESP32 telemetry protocol as the
Android app.

## Status: source-complete, logic verified, NEVER COMPILED

This is a Windows machine: **no macOS, no Xcode, no iOS Simulator**. The Swift
has never been through a compiler. What *has* been done:

| Check | Result |
|---|---|
| iOS logic simulation (`tests/test_ios_logic_sim.py`) | **34/34 pass** |
| Swift source brace/paren balance | all 6 files balanced |
| `project.yml` + workflow YAML parse | valid, targets/schemes wired correctly |
| Swift compilation | **never attempted** — impossible here |
| Runs in an iOS Simulator | **never** — no simulator exists on Windows |

The logic simulation mirrors `TelemetryFormatter.swift` and the decode rules,
then runs the *same fixtures* and asserts the *same strings* as the XCTest suite.
So behaviour is proven; only compilation is not.

## Building it — two paths

### A. CI (works from Windows, recommended)

`.github/workflows/ios.yml` builds and tests on a GitHub macOS runner:

- installs XcodeGen, generates the Xcode project from `project.yml`
- runs the XCTest suite on the **iPhone 15 simulator**
- archives an **unsigned `.ipa`** and uploads it as a build artifact

Push the repo to GitHub, open the **Actions** tab, run *iOS build and test*, then
download the `GeorgePPM-unsigned-ipa` artifact.

### B. Locally on a Mac

```bash
brew install xcodegen
cd ios
xcodegen generate          # creates GeorgePPM.xcodeproj from project.yml
open GeorgePPM.xcodeproj   # then Run on a physical iPhone
```

The iOS Simulator has **no Bluetooth radio**, so it can verify the UI and unit
tests but never the BLE link. Hardware testing needs a real iPhone.

## Installing the .ipa on an iPhone

iOS has no equivalent of "install unknown APK". An unsigned `.ipa` will not
install on a stock iPhone — it must be signed with an Apple ID:

| Path | Cost | Expiry |
|---|---|---|
| Sideloadly / AltStore on Windows, free Apple ID | free | 7 days, re-sign weekly |
| Xcode + USB, free Apple ID | needs a Mac | 7 days |
| TestFlight | $99/yr Apple Developer | 90 days per build |
| Ad Hoc | $99/yr + registered UDIDs | 1 year |

## Behaviour

Same protocol as Android (`docs/BLE_PROTOCOL.md`):

- Scans filtered by service UUID `4a5b6c7d-0001-…`
- Subscribes to the telemetry characteristic `…0002…`
- Parses the JSON frame once per second
- `Reset Total` writes `RESET` to `…0003…`
- **Simulation mode** generates synthetic frames, so the UI can be exercised
  with no board at all

## iOS-specific notes

| Topic | iOS behaviour |
|---|---|
| MTU | **Cannot be requested.** CoreBluetooth negotiates (~185 bytes), far above our 67-byte frame |
| CCCD / descriptor | CoreBluetooth writes the notify descriptor itself on `setNotifyValue(true, for:)` |
| Scan filtering | Filters on the **advertisement** packet — the firmware puts the 128-bit UUID there and the name in the scan response |
| RSSI | Not pushed; polled with `readRSSI()` every 5 s |
| Background | Not configured; add the `bluetooth-central` background mode if needed |

## Files

| File | Purpose |
|---|---|
| `project.yml` | XcodeGen spec — generates the .xcodeproj, so no hand-written pbxproj |
| `GeorgePPM/GeorgePPMApp.swift` | `@main` entry point |
| `GeorgePPM/ContentView.swift` | SwiftUI UI: metric cards, connection detail, event log, simulation toggle |
| `GeorgePPM/BleCentral.swift` | CoreBluetooth central: scan → connect → discover → subscribe → parse |
| `GeorgePPM/Telemetry.swift` | `Decodable` frame model |
| `GeorgePPM/TelemetryFormatter.swift` | display formatting, kept SwiftUI-free so it is unit-testable |
| `GeorgePPM/Simulator.swift` | synthetic telemetry for hardware-free testing |
| `GeorgePPMTests/TelemetryTests.swift` | XCTest suite, runs on the simulator in CI |
