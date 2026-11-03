# Wiring — George PPM

Board: **ESP32-D0WD-V3** (4 MB flash, MAC `20:e7:c8:ad:a8:b0`), MicroPython v1.29.0.

## Pin map

| Signal | ESP32 pin | Sensor supply | Conditioning required |
|---|---|---|---|
| LCD SCL | **GPIO18** | 3V3 | none |
| LCD SDA | **GPIO19** | 3V3 | none |
| YF-S201 flow | **GPIO27** | 5 V | 1 kΩ series + 2 kΩ to GND (5 V → 3.33 V) |
| LJ12A3-4-Z/BX proximity | **GPIO26** | **12 V** | 10 kΩ pull-up to 3V3 (NPN open collector) |
| ACS712 current | **GPIO34** | 5 V | 10 kΩ series + 20 kΩ to GND (5 V → 3.33 V) |
| Battery divider | **GPIO35** | — | 47 kΩ series + 10 kΩ to GND (14.8 V → 2.60 V) |

LCD is a 16×2 with a PCF8574 backpack at I²C address **0x27**.

## Supply rules (do not shortcut these)

| Device | Supply | Why |
|---|---|---|
| LCD | 3V3 | Already proven at 3.3 V; 5 V would put 5 V on the I²C pull-ups |
| YF-S201 | 5 V | Spec ~4.5–18 V; below 3.6 V it can miss pulses at low flow |
| LJ12A3 | **12 V** | Spec 6–36 V. **It will never trigger at 5 V or 3.3 V** |
| ACS712 | 5 V | Spec 4.5–5.5 V. Zero point is VCC/2 = 2.5 V |

Wire colours — YF-S201: red=VCC, black=GND, yellow=signal.
LJ12A3-4-Z/BX: brown=+V, blue=0V, black=OUT (NPN NO, idles HIGH via pull-up,
pulls LOW on metal → firmware counts falling edges).

**All grounds must be common.** The NPN proximity output references its own supply
ground; a floating ground is the classic cause of "the sensor LED blinks but the
ESP32 counts nothing".

## Power tree

```
12 V battery ──┬── LJ12A3 proximity (6-36 V — direct)
               ├── XH-M601 battery side
               └── buck converter (LM2596 / MP1584) ──► 5 V
                                                        ├── YF-S201
                                                        ├── ACS712
                                                        └── ESP32 VIN ──► 3V3 ──► LCD
```

Never power the ESP32 from the charger's 13.8–14.8 V output.

## XH-M601 battery charge controller

Not a mains device. 220 V feeds a **charger**; the module sits on its DC side.

```
220 V AC ──► CHARGER ──(13.8-14.8 V DC)──► IN+ / IN- of XH-M601
                                          OUT+ / OUT- ──► 12 V lead-acid battery
```

| Parameter | Value |
|---|---|
| Power supply voltage | 13.8–14.8 V DC |
| Relay start-charge voltage (RP1) | 12.4 V |
| Relay disconnect voltage (RP2) | 14.8 V |
| Tolerance | ±0.1 V |

The relay is a **series switch** between charger and battery. Datasheet PDF:
`datasheets/xh601.pdf`.

## Divider maths (so the numbers can be checked)

- Flow, 1k/2k: Vout = Vin × 2/(1+2) = 0.6667 × 5 V = **3.33 V**
- ACS712, 10k/20k: 0.6667 × 4.5 V = **3.00 V max**; zero-current 2.5 V → **1.667 V**
- Battery, 47k/10k: 14.8 V × 10/57 = **2.60 V**; 12.0 V → 2.11 V
