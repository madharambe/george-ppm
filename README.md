# George PPM — water flow / RPM / current monitor

ESP32 monitoring rig with a 16×2 LCD and a BLE link to an Android app.

> **All docs live in `docs/`.** Start with `docs/WIRING.md` before powering anything.

## What it measures

| Channel | Sensor | Pin |
|---|---|---|
| Flow rate + total volume | YF-S201 (450 pulses/litre) | GPIO27 |
| Shaft RPM | LJ12A3-4-Z/BX inductive proximity | GPIO26 |
| Current draw | ACS712 Hall current sensor | GPIO34 |
| Battery voltage | resistor divider (optional) | GPIO35 |
| Local display | 16×2 LCD, PCF8574 @ 0x27 | GPIO18/19 |

Plus an **XH-M601** 12 V lead-acid charge controller on the battery side
(datasheet in `datasheets/xh601.pdf`).

## Layout

```
George PPM/
├── firmware/            MicroPython on the ESP32
│   ├── main.py          sampling loop + LCD pages + BLE publish
│   ├── sensors.py       Flow / Rpm / CurrentSensor / BatterySensor
│   ├── ble_link.py      BLE GATT server (telemetry notify + commands)
│   └── lcd.py           HD44780 over PCF8574
├── android/             Kotlin BLE client app  (see android/README.md)
├── ios/                 SwiftUI + CoreBluetooth app (see ios/README.md)
├── tests/               firmware logic tests, run under CPython
├── docs/
│   ├── WIRING.md        full pin map, supply rules, dividers, power tree
│   ├── BLE_PROTOCOL.md  UUIDs, JSON frame, MTU, commands
│   └── RESEARCH.md      Android BLE findings + what is/isn't verified
├── datasheets/          xh601.pdf
├── backup/              original 4 MB flash dump + MicroPython firmware
└── tools/
    ├── flash.py         push firmware/ to the board over serial
    └── _esplibs/        esptool 4.8.1 (for flashing/backup)
```

## Quick start

```powershell
# 1. flash the firmware (board must be reachable on its COM port)
python tools/flash.py COM10

# 2. see the live frame on the serial port
#    {"f":12.34,"t":45.67,"r":1450,"a":1.23,"v":12.64,"c":1,"ms":123456}
```

Verify the BLE link with **nRF Connect for Mobile** (scan for `GeorgePPM`, enable
notifications on characteristic `...0002...`) before building the app.

## LCD pages

The 16×2 display cycles every 3 seconds:

```
Debit  12.34 L/m        Arus    1.23 A        Bat  12.64 V
RPM      1450           Total   45.67 L       BLE        1
```

## Status — honest accounting

| Piece | State |
|---|---|
| Firmware | **Running on the board, verified.** Telemetry JSON captured off serial |
| BLE GATT server | **Verified** — advertises as `GeorgePPM`, MTU 247 accepted |
| LCD driver | **Verified** — contrast pot adjusted, text legible |
| Sensor inputs | Wired per `docs/WIRING.md`; ACS712 not yet reporting (divider/sensor not connected), firmware shows `Arus -- A` rather than a fake number |
| Firmware logic tests | **35/35 pass** (`python tests/test_firmware_logic.py`) — found and fixed a real RPM bug |
| Android app | **Not compiled** — no Android SDK/Gradle on this machine (see `docs/RESEARCH.md` §5) |
| iOS logic (Swift 6.4.2 on Windows) | **91/91 pass** — 5 of 9 files compiled + executed |
| iOS source verification | **9 of 9 files** — the other 4 type-check against CoreBluetooth/Combine/SwiftUI shims (mutation-tested) |
| iOS project preflight | **61/61 pass** — delegate selectors vs Apple docs, and BLE contract firmware ↔ iOS ↔ Android |
| iOS app as a whole | **BUILT + TESTED** — CI run 41797491054, macos-15, 7/7 XCTest passed |
| APK | **Exists** — `android/app/build/outputs/apk/debug/app-debug.apk` (5.60 MB, signed) |
| .ipa | **Exists** — `ios/build/GeorgePPM-unsigned.ipa` (61 KB, arm64, unsigned) |

## Board quirks worth remembering

- **No DTR/RTS auto-reset.** Flashing MicroPython needs *hold BOOT → tap RST →
  release BOOT*, then `--before no_reset`.
- **MicroPython has no `str.ljust`/`rjust`/`center`** — pad manually.
- **`ADC.read()` returns 0 on GPIO34/35 on this build**; `read_uv()` works. All
  analog reads go through `read_uv()` with a raw fallback.
- **PowerShell/curl HTTPS is broken here** (`schannel SEC_E_NO_CREDENTIALS`); use
  Python for downloads.
