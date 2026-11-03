# BLE protocol — George PPM

## Advertisement

- Device name: **GeorgePPM**
- Advertising data: flags (3 B) + 128-bit service UUID list (18 B) = 21 B
- Scan response: complete local name (11 B)

**The split matters.** CoreBluetooth (iOS) filters scans on the *advertisement*
packet, so the service UUID must live there. Android merges both packets, so it
works either way — but advertising the name and putting the UUID in the scan
response silently breaks iOS discovery. Verified byte layout in
`tests/test_firmware_logic.py`.
- Platform: ESP32 classic — **BLE only**, no Bluetooth Classic / SPP. MicroPython
  on ESP32 exposes BLE exclusively, so an SPP-based app cannot work here.

## GATT

| | UUID | Properties |
|---|---|---|
| Service | `4a5b6c7d-0001-4d8e-9f00-a1b2c3d4e5f6` | — |
| Telemetry | `4a5b6c7d-0002-4d8e-9f00-a1b2c3d4e5f6` | READ + NOTIFY |
| Command | `4a5b6c7d-0003-4d8e-9f00-a1b2c3d4e5f6` | WRITE + WRITE_NO_RESPONSE |

CCCD descriptor on the telemetry characteristic: `00002902-0000-1000-8000-00805f9b34fb`.

## Telemetry frame (ASCII JSON, ~62 bytes)

```json
{"f":12.34,"t":45.67,"r":1450,"a":1.23,"v":12.64,"c":1,"ms":123456}
```

| Key | Meaning | Units |
|---|---|---|
| `f` | flow rate | L/min |
| `t` | total volume since boot / last RESET | L |
| `r` | RPM (0 when the shaft is stopped) | rev/min |
| `a` | current, 0 when the ACS712 is absent/out of range | A |
| `v` | battery voltage, **null** when the divider is not fitted | V |
| `c` | connected BLE clients | count |
| `ms` | ESP32 uptime | ms |

Published once per second via notify.

## MTU

The frame is ~62 bytes. The BLE default ATT MTU is 23 (20-byte payload), which
would **truncate it**. Firmware calls `BLE.config(mtu=247)`; the Android client
calls `requestMtu(247)`. Both sides are needed:

- Verified on the device: `config(mtu=247)` is accepted and reads back 247.
- If a client does not negotiate, notifications will fail or arrive cut short.

## Commands (write to the command characteristic)

| Command | Effect |
|---|---|
| `RESET` | zero the accumulated total volume |
| `ZERO` | re-capture the ACS712 zero-current offset |
| anything else | echoed back in the serial log only |

## Verifying without building an app

Use **nRF Connect for Mobile** (Android/iOS): scan for `GeorgePPM`, connect,
open the service, enable notifications on `...0002...`. You should see the JSON
frame update once a second. That proves the whole firmware side before any APK
exists.
