# George PPM Monitor — iOS app

SwiftUI + CoreBluetooth client for the same ESP32 telemetry protocol as the
Android app.

## Status: source-complete, NEVER COMPILED

This is a Windows machine, so there is **no macOS and no Xcode** here. The Swift
below has never been run through a compiler, and has never been on a device or
simulator. Treat the first Xcode build as the real test.

There is deliberately **no `.xcodeproj`**. A hand-written `project.pbxproj` of
that size, generated blind and unverifiable, would more likely fail to open than
help. Creating the project in Xcode takes about a minute (below).

## Setup in Xcode

1. **Xcode → File → New → Project → iOS → App**
   - Interface: **SwiftUI**, Language: **Swift**
   - Name: `GeorgePPM`
2. Delete the generated `ContentView.swift` and `<name>App.swift`.
3. Drag these four files into the project (Copy items if needed):
   - `GeorgePPM/ContentView.swift`
   - `GeorgePPM/GeorgePPMApp.swift`
   - `GeorgePPM/BleCentral.swift`
   - `GeorgePPM/Telemetry.swift`
   - `GeorgePPM/Simulator.swift`
4. Set the minimum deployment target to **iOS 16.0** (uses `Toggle`, `@StateObject`
   and `onChange(of:)`; bump if Xcode complains about the `onChange` signature).
5. Add the Bluetooth usage strings. Either point the target at `ios/Info.plist`,
   or paste these keys into the target's Info settings:
   - `NSBluetoothAlwaysUsageDescription` — required on iOS 13+, **the app will
     crash on first scan without it**
   - `NSBluetoothPeripheralUsageDescription` — legacy, harmless to include
6. Run on a **physical iPhone**. The iOS Simulator has no Bluetooth radio.

## Behaviour

Same protocol as Android (`docs/BLE_PROTOCOL.md`):

- Scans filtered by service UUID `4a5b6c7d-0001-…`
- Subscribes to the telemetry characteristic `…0002…`
- Parses the JSON frame once per second
- `Reset Total` writes `RESET` to `…0003…`
- **Simulation mode** generates synthetic frames so the UI can be exercised with
  no board at all

## iOS-specific notes

| Topic | iOS behaviour |
|---|---|
| MTU | **Cannot be requested.** CoreBluetooth negotiates automatically (~185 bytes), well above our 67-byte frame, so nothing needed |
| CCCD / descriptor | CoreBluetooth writes the notify descriptor itself when `setNotifyValue(true, for:)` is called |
| Scan filtering | Filters on the **advertisement** packet — this is why the firmware puts the 128-bit UUID in the advertisement and the name in the scan response |
| RSSI | Not pushed; polled with `readRSSI()` on a 5 s timer |
| Background | Not configured. Add the `bluetooth-central` background mode if you need updates while backgrounded |

## Files

| File | Purpose |
|---|---|
| `GeorgePPM/GeorgePPMApp.swift` | `@main` entry point |
| `GeorgePPM/ContentView.swift` | SwiftUI UI: metric cards, connection detail, event log, simulation toggle |
| `GeorgePPM/BleCentral.swift` | CoreBluetooth central: scan → connect → discover → subscribe → parse |
| `GeorgePPM/Telemetry.swift` | `Decodable` frame model |
| `GeorgePPM/Simulator.swift` | synthetic telemetry for hardware-free testing |
| `Info.plist` | Bluetooth usage descriptions and launch screen |
