# Research notes — Android app for ESP32 status over Bluetooth

Compiled from live sources on this machine, plus what was measured on the actual
board. Everything marked **verified** was tested here; everything marked
**unverified** was not, and is labelled so on purpose.

## 1. Which Bluetooth does this ESP32 actually have?

The chip is an ESP32-D0WD-V3, which contains **both** Bluetooth Classic and BLE 4.2
radios. But **MicroPython on ESP32 only exposes BLE** — there is no SPP/Classic
serial profile. Verified on the device:

```
bluetooth module OK
has BLE: True
BLEService/characteristic API: gap_advertise, gatts_register_services, gatts_notify
```

**Consequence:** any tutorial that says "pair with a BT serial terminal and send
commands" (HC-05 style / SPP) cannot work here. The app must be a **BLE GATT
central**.

Also measured, and not obvious from the docs:
- `BLE.config('mac')` returns a **tuple**, not the 6-byte `bytes` that older docs imply.
- IRQ event constants (`_IRQ_CENTRAL_CONNECT` etc.) are **not exported** on this
  build — only `FLAG_*` are. The firmware uses numeric IDs with getattr fallbacks.
- `BLE.config(mtu=247)` **is** supported and reads back as 247.

## 2. Android permissions — the part that breaks most apps

Android changed Bluetooth permissions at API 31, and the split is the single most
common cause of "scan finds nothing". From the Android developer documentation
(*Bluetooth permissions*, developer.android.com/develop/connectivity/bluetooth/bt-permissions):

| Target | Declare | Request at runtime |
|---|---|---|
| API 31+ | `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` | both, at runtime |
| API ≤ 30 | `BLUETOOTH`, `BLUETOOTH_ADMIN` (install-time) | `ACCESS_FINE_LOCATION` |

Two details that matter:
- `android:usesPermissionFlags="neverForLocation"` on `BLUETOOTH_SCAN` states you do
  not derive physical location from scan results, which lets you skip
  `ACCESS_FINE_LOCATION` on API 31+.
- On API ≤ 30, if location permission is missing, scans return **zero results with
  no error**. Silent failure, not an exception.

Google Play additionally requires new submissions to target **Android 16 (API 36)**
from **31 August 2026** (developer.android.com/google/play/requirements/target-sdk).
Irrelevant for a sideloaded APK, so this project targets 35 — raise it if it ever
goes to Play.

## 3. GATT pitfalls that cost real debugging time

1. **Reconnect leaks the client interface.** `disconnect()` does not release the
   BluetoothGatt client. Calling `connectGatt()` again without `close()` first can
   return null or hang. The client therefore always does `close()` in its teardown
   path (and a dedicated `closeGatt()` helper).
2. **Notifications need the CCCD descriptor written.** `setCharacteristicNotification()`
   alone is not enough; the client must write `ENABLE_NOTIFICATION_VALUE` to
   `00002902-...`.
3. **API 33 changed the callback signature.** `onCharacteristicChanged(gatt, char, value)`
   is the new one; the two-argument form is deprecated. Both are overridden, with a
   version guard so frames are not handled twice.
4. **MTU.** Default ATT MTU is 23 bytes (20 usable). Our JSON frame is ~62 bytes, so
   without negotiation it truncates. Firmware sets 247; client calls `requestMtu(247)`
   then discovers services on `onMtuChanged`, with a 2.5 s fallback because some
   stacks never deliver that callback.
5. **Descriptor write API changed at 33 too** — `writeDescriptor(desc, value)` vs the
   deprecated `desc.setValue()` + `writeDescriptor(desc)`.

## 4. Framework choice

| Option | Verdict |
|---|---|
| **Native Kotlin** (chosen) | Full control of GATT, permissions and the API-33 overloads; no plugin layer hiding the failure modes above |
| Flutter + flutter_blue_plus | Good cross-platform choice, but adds a whole SDK to install and a plugin between you and the GATT callbacks |
| React Native + react-native-ble-plx | Same trade-off, heavier toolchain |
| MIT App Inventor | No local build needed, tempting for coursework — but BLE needs the BluetoothLE extension, and the resulting project file cannot be generated or verified offline |

Native Kotlin won because the deliverable is a *reliable* status display, and the
known pitfalls are all at the native API level.

## 5. What is verified vs. not

### Verified here
- BLE stack works on this exact chip; GATT server registers, notifies, and the
  telemetry JSON is produced once per second (captured off the serial port).
- MTU 247 accepted and echoed back by the firmware.
- The Android **manifest and permission model** match the current Android docs.
- Registry/serial facts: board on COM10, CP210x bridge, 4 MB flash.

### NOT verified — stated plainly
- **The Android app has never been compiled.** This machine has JDK 21, but **no
  Android SDK, no Gradle, no adb and no Android Studio**. Downloading the SDK is
  ~300 MB and this link stalls on large transfers (it needed 64 KB ranged chunks to
  pull a 1.8 MB firmware file), so building here was not attempted.
- No APK was produced. The project is source-complete and laid out for Android
  Studio, but first-build errors are possible and should be expected.
- The app has never talked to the board. The BLE link was proven firmware-side only.

## 6. Cheapest way to verify the link today

Install **nRF Connect for Mobile**, scan for `GeorgePPM`, connect, and enable
notifications on the `...0002...` characteristic. If the JSON updates once a second,
the entire firmware side is confirmed and any problem left is in the app.
