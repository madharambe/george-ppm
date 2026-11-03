# main.py - George PPM: flow + RPM + current + battery, LCD + BLE telemetry
#
# Pins
#   LCD SCL GPIO18 / SDA GPIO19 (0x27)
#   YF-S201 flow      GPIO27   (5V, 1k/2k divider)
#   LJ12A3 prox       GPIO26   (12V, NPN OC, 10k pull-up to 3V3)
#   ACS712 current    GPIO34   (5V, 10k/20k divider)
#   Battery divider   GPIO35   (47k/10k)   optional
import time
import lcd
import sensors
import ble_link
from machine import Pin, I2C

I2C_SCL, I2C_SDA, LCD_ADDR = 18, 19, 0x27
PIN_FLOW = 27
PIN_PROX = 26
PIN_ACS = 34
PIN_BAT = 35

FLOW_PPL = 450.0          # YF-S201 pulses per litre
RPM_PPR = 1               # targets per revolution
SAMPLE_MS = 1000
PAGE_EVERY = 3            # LCD page rotation, in samples
PRINT_EVERY = 5           # keep serial quiet so re-flashing stays possible


def pad(s, width):
    s = str(s)
    return s[:width] if len(s) >= width else s + " " * (width - len(s))


def rpad(s, width):
    s = str(s)
    return s[:width] if len(s) >= width else " " * (width - len(s)) + s


def start_lcd(retries=5):
    for _ in range(retries):
        try:
            i2c = I2C(0, scl=Pin(I2C_SCL), sda=Pin(I2C_SDA), freq=100000)
            time.sleep_ms(100)
            if LCD_ADDR in i2c.scan():
                return lcd.Lcd(i2c, LCD_ADDR, cols=16, rows=2)
        except Exception:
            pass
        time.sleep_ms(300)
    return None


def show(d, text, row):
    d.text(pad(text, 16), 0, row)


def main():
    flow = sensors.Flow(PIN_FLOW, FLOW_PPL)
    rpm_s = sensors.Rpm(PIN_PROX, RPM_PPR)
    cur = sensors.CurrentSensor(PIN_ACS)
    bat = sensors.BatterySensor(PIN_BAT)

    ok, v = cur.autozero()
    print("acs autozero:", ok, round(v, 3))

    state = {"cmd": "-"}

    def on_command(msg):
        m = msg.strip().upper()
        state["cmd"] = m
        if m == "RESET":
            flow.reset()
        elif m == "ZERO":
            cur.autozero()
        print("cmd:", m)

    link = ble_link.BleLink(on_command=on_command)
    print("BLE advertising as GeorgePPM")

    d = start_lcd()
    if d:
        d.clear()
        show(d, "George PPM", 0)
        show(d, "starting...", 1)
        print("LCD ready")

    last = time.ticks_ms()
    tick = 0

    while True:
        time.sleep_ms(100)
        now = time.ticks_ms()
        dt = time.ticks_diff(now, last)
        if dt < SAMPLE_MS:
            continue
        last = now
        tick += 1

        flow.sample(dt)
        rpm = rpm_s.value()
        amps = cur.sample()
        bat.sample()

        payload = '{"f":%.2f,"t":%.2f,"r":%d,"a":%s,"v":%s,"c":%d,"ms":%d}' % (
            flow.lpm, flow.total_l, rpm,
            ("%.2f" % amps) if cur.ok else "null",
            ("%.2f" % bat.volts) if bat.ok else "null",
            link.connected(), time.ticks_ms() & 0x7FFFFFFF)
        link.publish(payload)

        if d:
            page = (tick // PAGE_EVERY) % 3
            if page == 0:
                show(d, "Debit " + rpad("%.2f" % flow.lpm, 6) + " L/m", 0)
                show(d, "RPM " + rpad(str(rpm), 9), 1)
            elif page == 1:
                show(d, "Arus " + rpad(("%.2f" % amps) if cur.ok else "--", 7) + " A", 0)
                show(d, "Total " + rpad("%.2f" % flow.total_l, 6) + " L", 1)
            else:
                show(d, "Bat " + rpad(("%.2f V" % bat.volts) if bat.ok else "--", 8), 0)
                show(d, "BLE " + rpad(str(link.connected()), 10), 1)

        if tick % PRINT_EVERY == 0:
            print(payload)


main()
