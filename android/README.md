# George PPM Monitor — Android app

Reads live telemetry from the ESP32 over BLE and shows debit, total, RPM, current
and battery voltage.

## Status: source-complete, NOT yet compiled

This machine has **JDK 21 but no Android SDK, no Gradle, no adb and no Android
Studio**, so the project has never been built. Expect to fix small first-build
issues; nothing here has been proven on a device.

## Build

1. Install **Android Studio** (any recent version; this project targets SDK 35).
2. `File → Open` → select this `android/` folder.
3. Let it sync. Android Studio will fetch Gradle 8.9 and the SDK components.
4. Run on a **physical phone** — emulators have no Bluetooth radio.

Command line alternative, once the SDK exists:

```bash
cd android
gradle wrapper          # only if gradle/wrapper/gradle-wrapper.jar is missing
./gradlew assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk
```

## Using it

1. Enable Bluetooth on the phone.
2. Tap **Scan & Connect**; grant the Bluetooth permissions when asked.
3. It looks for the **GeorgePPM** service UUID and connects automatically.
4. Values refresh once a second. The log at the bottom shows every GATT step
   (MTU, subscribe result, errors) — that log is the first place to look when
   something does not connect.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Scan finds nothing | Bluetooth off, or permission denied. On Android ≤ 11, missing location permission makes scans return *zero results with no error* |
| Connects then drops immediately | Another app still holds the GATT client. Force-stop it, or toggle Bluetooth |
| Connected but values never update | CCCD subscribe failed — check the log for "Subscribe failed" |
| Truncated / unparseable frames | MTU negotiation failed; the log shows the negotiated MTU |
| Nothing connects at all | ESP32 not powered or firmware not running |

## Files

| File | Purpose |
|---|---|
| `MainActivity.kt` | permissions, UI, wiring of callbacks |
| `BleClient.kt` | scan → connect → MTU → discover → subscribe → notify |
| `Telemetry.kt` | JSON frame parser |
| `AndroidManifest.xml` | API 31+ and ≤30 permission split, `neverForLocation` |
