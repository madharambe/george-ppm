# George PPM Monitor — iOS app

SwiftUI + CoreBluetooth client for the same ESP32 telemetry protocol as the
Android app.

## Status: partially COMPILED and RUN with a real Swift compiler

A **Swift 6.4.2 toolchain was installed on this Windows machine** (winget
`Swift.Toolchain`, per-user, alongside the already-present MSVC 2022 + Windows
SDK). That means the Foundation-only half of the app is genuinely compiled and
executed here, not merely simulated.

| Check | Result |
|---|---|
| **Swift compile + run** (`tools/swift_harness.cmd`) | **91/91 pass** — real swiftc, real execution |
| iOS logic simulation (`tests/test_ios_logic_sim.py`) | **34/34 pass** |
| Project preflight (`tools/ios_preflight.py`) | **61/61 pass** |
| CoreBluetooth delegate selectors vs Apple docs | 10/10 exact match |
| BLE contract firmware ↔ iOS ↔ Android | 3 UUIDs + device name all match |
| CI lint (`tools/ci_lint.py`) | **17/17 pass** — bash syntax, picker on 4 runner images, runner label not retired, action majors current |
| Builds as an iOS app | **still never** — needs Xcode/macOS |
| Runs in the iOS Simulator | **never** — no simulator on Windows |

### Exactly what compiles here, and what cannot

```
Telemetry.swift           COMPILES + RUNS   Foundation only
TelemetryFormatter.swift  COMPILES + RUNS   Foundation only
BleSpec.swift             COMPILES + RUNS   Foundation only  (BLE contract + LinkState)
SyntheticTelemetry.swift  COMPILES + RUNS   Foundation only  (demo data generator)
Dashboard.swift           COMPILES + RUNS   Foundation only  (all display wording + status)
BleCentral.swift          needs CoreBluetooth   -> error: no such module 'CoreBluetooth'
Simulator.swift           needs Combine         -> ObservableObject / @Published unknown
ContentView.swift         needs SwiftUI         -> error: no such module 'SwiftUI'
GeorgePPMApp.swift        needs SwiftUI         -> error: no such module 'SwiftUI'
```

**5 of 9 files compile and execute here.** The four that cannot are exactly the
Apple-framework layer: the CoreBluetooth adapter, the Combine wrapper, and the two
SwiftUI files. `ContentView` is now almost pure layout — every string it shows,
and every "sensor absent" decision, comes from `Dashboard`, which *is* tested.

The refactor was deliberate: the BLE contract (UUIDs, device name, commands,
`LinkState`), the synthetic-data generator and the presentation logic were pulled
out of the Apple-only files into Foundation-only ones, so the parts most likely to
silently drift are compiled and tested on every run.

Check the boundary yourself:

```powershell
cmd /c "George PPM\tools\swift_boundary.cmd"
```

### Running the Swift harness

```powershell
cmd /c "George PPM\tools\swift_harness.cmd"
```

It compiles the two Foundation files plus `tests/swift/main.swift` against the
Windows SDK and runs the same assertions as the XCTest suite. Note the toolchain
needs an explicit `-sdk` pointing at
`%LOCALAPPDATA%\Programs\Swift\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk`,
and `vcvars64.bat` for linking — both handled inside the .cmd.

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
