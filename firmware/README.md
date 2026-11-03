# ESP32 + I2C LCD (16x2) — working setup

Verified 2026-10-11 on this machine.

## Hardware
| Item | Value |
|------|-------|
| Board | ESP32-D0WD-V3 (rev v3.1), dual-core, 4 MB flash |
| MAC | 20:e7:c8:ad:a8:b0 |
| USB bridge | Silicon Labs CP210x -> **COM10** |
| LCD I2C address | **0x27** (PCF8574 backpack) |
| Wiring | LCD SCL -> GPIO18, LCD SDA -> GPIO19, VCC 3V3, GND |

## Contrast (this is what made text angle-dependent)
The display initially showed text only from an oblique angle. That is the **analog
contrast pot (V0)** on the backpack sitting outside the usable window, not a driver
bug. Fixed by turning the small trimpot on the back of the backpack until a solid
block pattern (`chr(255)*16`) looked crisp from straight ahead.

Resolution: **staying at 3V3 is fine** — no level shifter needed. The HD44780 is a 5 V
part, but with the pot adjusted it reads well at 3.3 V, which keeps the I2C bus
in spec (5 V VCC would put 5 V on GPIO18/19 through the backpack's pull-ups).

## I2C reliability baseline (3V3, 100 kHz)
200/200 scans, 2000/2000 single-byte writes, **0 errors**. Re-run this after any
rewiring or if the display ever starts glitching:
```python
from machine import Pin, I2C
import time
i2c = I2C(0, scl=Pin(18), sda=Pin(19), freq=100000)
time.sleep_ms(100)
errs = sum(1 for _ in range(200) if not i2c.scan())
for i in range(2000):
    try: i2c.writeto(0x27, bytes([0x08 | (i & 0xF0)]))
    except Exception: errs += 1
print("errors", errs)
```

## Sensors: water flow + RPM

| Signal | ESP32 pin | Interface |
|---|---|---|
| LCD SCL | **GPIO18** | direct |
| LCD SDA | **GPIO19** | direct |
| YF-S201 flow signal | **GPIO27** | 1k series + 2k to GND (5V -> 3.33V) |
| LJ12A3-4-Z/BX output | **GPIO26** | 10k pull-up to 3V3 (NPN open collector) |
| YF-S201 VCC | 5V (VIN) | sensor needs 5-24V |
| LJ12A3 VCC | **12V** | sensor needs 6-36V, will NOT work at 5V |
| All GND | GND | common ground is mandatory |

Wire colours: **YF-S201** red=VCC, black=GND, yellow=signal.
**LJ12A3-4-Z/BX** brown=+V, blue=0V, black=OUT (NPN NO: idles HIGH via pull-up,
pulls LOW on a metal target -> firmware counts FALLING edges).

## ACS712 current sensor (NOT a voltage sensor)

The ACS712 is a **Hall-effect current sensor**: it outputs an analog voltage
proportional to the current through its primary conductor, **2.5 V at 0 A**
(bidirectional part), `185 mV/A` on the ±5 A version. It does not measure volts.

| Signal | ESP32 pin | Interface |
|---|---|---|
| ACS712 OUT | **GPIO34** (ADC1_CH6) | **10k + 20k divider** (5 V -> 3.33 V) |
| ACS712 VCC | 5 V | the sensor needs 5 V |
| ACS712 GND | GND | common |

**Why the divider is mandatory:** the output swings 0.5-4.5 V. 4.5 V exceeds the
ESP32's 3.6 V pin limit. R1 = 10 kΩ (OUT -> node), R2 = 20 kΩ (node -> GND) gives
ratio 0.6667, so 4.5 V becomes 3.0 V. Zero current sits at 2.5 V -> **1.667 V at the pin**.

Sensitivity after the divider: `185 mV/A x 0.6667 = 123 mV/A`.
Set `ACS_MV_PER_A` to match your variant: **-05B = 185**, **-20A = 100**, **-30A = 66**.

Resolution reality check: 12-bit over 3.3 V is ~0.8 mV per LSB at the pin, so with the
divider that is roughly **6 mA per count** and far worse in practice because the ESP32
ADC is noisy and non-linear. Averaging is applied (24 samples). Do not trust this for
tens of milliamps; it is a coarse amps-scale reading.

### Wanted actual VOLTAGE? Different circuit
A voltage divider from the measured bus into any ADC1 pin, e.g. **30 kΩ + 10 kΩ** for a
12 V bus (12 x 10/40 = 3.0 V). That is a separate sensor, not the ACS712.

### MicroPython ADC gotcha found on this build
`ADC.read()` returns **0** on GPIO34/35 here, while `read_uv()` returns sensible
calibrated microvolts. `adc_volts()` therefore uses `read_uv()` with a raw fallback.
`esp32.ADC` does not exist in this build - the ATTN/WIDTH constants live on
`machine.ADC`, so the code falls back to `ADC.ATTN_11DB` / `ADC.WIDTH_12BIT`.

The firmware also sanity-checks the sensor: if the reconstructed sensor output falls
outside 1.0-4.0 V it assumes the sensor is absent, shows `Arus -- A`, and refuses to
report a bogus current.

### Calibration constants (top of main.py)
- `FLOW_PPR = 450.0` - YF-S201 pulses per litre. Verify by filling a measured
  1 litre and comparing the `Total` reading.
- `RPM_PPR = 1` - number of targets per revolution (1 bolt per rev = 1;
  4 bolts on a shaft = 4).
- `SAMPLE_MS = 1000` - sample window. `RPM_TIMEOUT_US = 2 s`, so below 30 RPM
  the display shows 0.

### Display
```
Debit  12.34 L/m     <- line 1, live flow
RPM      1450        <- line 2, alternates every 6 s with "Total   123.45 L"
```

### MicroPython gotchas found here
- **No `str.ljust`/`rjust`/`center`** in MicroPython - pad manually (`pad()`/`rpad()`
  in main.py). Using them raises `AttributeError` at runtime.
- Interrupt handlers only increment integers; no float maths inside an IRQ.

## Firmware
MicroPython v1.29.0 (2026-08-24, ESP32_GENERIC).

## Files on the board
- `boot.py` — left as shipped
- `lcd.py` — HD44780 driver over PCF8574 (4-bit mode)
- `main.py` — runs at boot, shows "Hello World" / "ESP32 + I2C LCD"

## Restore the ORIGINAL firmware (the WiFi sketch)
The full 4 MB flash dump taken before flashing:
```powershell
$env:PYTHONPATH = Join-Path $PWD "_esplibs"
# hold BOOT, tap RST, release BOOT first, then:
python -m esptool --port COM10 --before no_reset --after hard_reset -b 460800 write_flash -z 0x0 "_esp_flash\backup_original_4MB.bin"
```

## Re-flash MicroPython from scratch
```powershell
$env:PYTHONPATH = Join-Path $PWD "_esplibs"
python -m esptool --port COM10 --before no_reset --after hard_reset erase_flash
python -m esptool --port COM10 --before no_reset --after hard_reset -b 460800 write_flash -z 0x1000 "_esp_flash\ESP32_GENERIC-20260824-v1.29.0.bin"
```

## Gotchas learned here
- **The board's DTR/RTS auto-reset does not work** — esptool cannot enter download
  mode on its own. Hold **BOOT**, tap **RST/EN**, release BOOT, then use
  `--before no_reset`.
- **PowerShell / curl TLS is broken on this box** (schannel `SEC_E_NO_CREDENTIALS`),
  so `Invoke-WebRequest` and `curl.exe` fail for HTTPS. Python's OpenSSL works —
  download with Python, not with PowerShell.
- PyPI ships esptool as **sdist only** (no wheels); it is extracted under `_esplibs/`.
- Large HTTPS reads stall; pull big files in 64 KB ranged chunks.
- The first `i2c.writeto` right after creating I2C can return `ENODEV`; scan once
  (or retry) before driving the LCD.
- LCD backpack powered from 5 V would put ~5 V on GPIO18/19, which are not 5 V
  tolerant on ESP32 — power it from 3V3.
