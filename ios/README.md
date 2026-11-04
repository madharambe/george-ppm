# George PPM Monitor — iOS app

SwiftUI + CoreBluetooth client for the same ESP32 telemetry protocol as the
Android app.

## Status: BUILT, TESTED AND PACKAGED (2026-11-04)

The app was compiled by Xcode on a GitHub macOS runner and **all 7 XCTest cases
passed on the iOS Simulator**. A valid unsigned `.ipa` was produced.

```
run 41797491054 · macos-15 · 1m52s · conclusion: success
  ✓ xcodegen 2.46.0 generated GeorgePPM.xcodeproj
  ✓ xcodebuild test on the iPhone simulator — 7/7 passed
  ✓ xcodebuild archive -> GeorgePPM-unsigned.ipa
```

Verified inside the packaged `.ipa`:

| Key | Value |
|---|---|
| CFBundleIdentifier | `com.georgeppm.monitor` |
| CFBundleDisplayName | George PPM |
| MinimumOSVersion | 16.0 |
| UIDeviceFamily | `[1]` (iPhone) |
| UIRequiredDeviceCapabilities | `bluetooth-le`, `arm64` |
| NSBluetoothAlwaysUsageDescription | present |
| executable | 188,592 bytes, **Mach-O 64-bit arm64** |

Artifact: `ios/build/GeorgePPM-unsigned.ipa` (61,101 bytes, gitignored).

The sections below record how the source was verified *before* a Mac was
involved — that work is why the first real build passed without a single fix.

## Source verification before the build

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
| Spec vs XcodeGen docs (`tools/xcodegen_spec_check.py`) | **20/20 pass** — every key documented, target types valid, scheme refs resolve |
| iOS↔Android rendering parity (`tools/app_parity_check.py`) | **21/21 pass** — same decimals, same `--` sentinel, same labels/units |
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

**All 9 files are verified here.** Five compile and execute; the other four
type-check against hand-written shims of CoreBluetooth, Combine and SwiftUI
(`tools/swift_shim_check.cmd`).

| File | Lines | Verification |
|---|---|---|
| Telemetry / TelemetryFormatter / BleSpec / SyntheticTelemetry / Dashboard | 252 | **compiled + executed** (91 assertions) |
| BleCentral.swift | 255 | **type-checked** (CoreBluetooth + Combine shims) |
| Simulator.swift | 43 | **type-checked** (Combine shim) |
| ContentView.swift | 275 | **type-checked** (SwiftUI shim) |
| GeorgePPMApp.swift | 10 | **type-checked** (SwiftUI shim) |

### The shims are not trusted blindly

A shim that accepts everything is worthless, so `tools/swift_shim_mutation_test.cmd`
deliberately breaks the source and asserts the shim **rejects** it:

| Mutation | Result |
|---|---|
| misspelled modifier (`.foregroundColour`) | CAUGHT |
| wrong argument label (`.padding(hv: 16)`) | CAUGHT |
| type error (`Text(3.14)` where a String is required) | CAUGHT |
| removed `import Combine` from BleCentral | CAUGHT |
| unmodified sources | all 9 pass |

**What a pass proves:** our Swift is well-formed — no typos, wrong labels or type
errors — and the control flow and member names are consistent.

**What it does NOT prove:** that the shims match Apple's real frameworks, or that
anything renders correctly. The SwiftUI shim mirrors only the ~17 modifiers and
~16 view types this app uses. Real-framework compatibility is still only settled
by the CI build.

**The shim check found a real bug.** `BleCentral.swift` used `ObservableObject`
and `@Published` but only imported `Foundation` and `CoreBluetooth` — CoreBluetooth
does not re-export Combine, so the file would have failed to compile on iOS too.
Fixed by adding `import Combine`. That would otherwise have surfaced only after
a push and a macOS run.

`ContentView` is now almost pure layout — every string it shows, and every
"sensor absent" decision, comes from `Dashboard`, which *is* tested.

The refactor was deliberate: the BLE contract (UUIDs, device name, commands,
`LinkState`), the synthetic-data generator and the presentation logic were pulled
out of the Apple-only files into Foundation-only ones, so the parts most likely to
silently drift are compiled and tested on every run.

Check the boundary yourself:

```powershell
cmd /c "George PPM\tools\swift_boundary.cmd"           # what compiles natively
cmd /c "George PPM\tools\swift_shim_check.cmd"         # type-check all 9 files
cmd /c "George PPM\tools\swift_shim_mutation_test.cmd" # prove the shims have teeth
```

The shims live in `tests/swift/shims/` and are **never** part of the app target —
`project.yml` only compiles `GeorgePPM/` and `GeorgePPMTests/`.

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

### Why the .xcodeproj is not committed

Generating it needs XcodeGen. I tried to build XcodeGen from source here — Swift
6.4.2 and SwiftPM both work on this machine, and the source compiled its own
dependencies fine — but its dependency checkouts contain **symlinks**, and
Windows refuses to create those without Developer Mode or elevation. SwiftPM uses
libgit2, which ignores the usual `core.symlinks=false` workaround.

So the spec is validated against XcodeGen's own `ProjectSpec.md` instead
(`tools/xcodegen_spec_check.py`, 20/20). CI runs `xcodegen generate` on macOS
where symlinks are free.

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
