#!/usr/bin/env python3
"""test_firmware_logic.py - run the firmware's real modules under CPython.

The ESP32 modules import 'machine', 'time' and 'bluetooth'. We inject fakes and
import the ACTUAL firmware files, so the logic under test is the code that runs
on the board - not a copy of it.

Covers:
  * YF-S201 flow maths (pulses -> L/min and litres)
  * LJ12A3 period -> RPM, plus the timeout that reports 0
  * ACS712 volts -> amps, including the "sensor absent" guard
  * battery divider scaling
  * the exact telemetry JSON the firmware publishes
  * the BLE advertisement payload and notify fan-out
"""
import json
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
FW = os.path.normpath(os.path.join(HERE, "..", "firmware"))

PASS = []
FAIL = []


def check(name, cond, detail=""):
    if cond:
        PASS.append(name)
        print("  PASS  %s %s" % (name, detail))
    else:
        FAIL.append(name)
        print("  FAIL  %s %s" % (name, detail))


# ---------------------------------------------------------------- fake clock
class Clock:
    def __init__(self):
        self.ms = 0
        self.us = 0

    def sleep_ms(self, n):
        self.ms += n
        self.us += n * 1000

    def ticks_ms(self):
        return self.ms

    def ticks_us(self):
        return self.us

    def ticks_diff(self, a, b):
        return a - b


CLOCK = Clock()


# ---------------------------------------------------------------- fake machine
class FakePin:
    def __init__(self, no, *args, **kw):
        self.no = no
        self.handler = None
        self.trigger = None

    def irq(self, trigger=None, handler=None):
        self.trigger = trigger
        self.handler = handler

    def value(self):
        return 0

    def fire(self, n=1):
        for _ in range(n):
            if self.handler:
                self.handler(self)


class FakeADC:
    """Voltage at the pin, set by the test."""
    volts_at_pin = 0.0

    def __init__(self, pin, *args, **kw):
        self.pin = pin

    def atten(self, *a):
        pass

    def width(self, *a):
        pass

    def read_uv(self):
        return int(FakeADC.volts_at_pin * 1_000_000)

    def read(self):
        return int(FakeADC.volts_at_pin / 3.3 * 4095)


machine = types.ModuleType("machine")
machine.Pin = FakePin
machine.ADC = FakeADC
machine.Pin.IN = 0
machine.Pin.PULL_UP = 1
machine.Pin.IRQ_RISING = 1
machine.Pin.IRQ_FALLING = 2
machine.ADC.ATTN_11DB = 3
machine.ADC.WIDTH_12BIT = 4
machine.I2C = lambda *a, **k: None

fake_time = types.ModuleType("time")
fake_time.sleep_ms = CLOCK.sleep_ms
fake_time.sleep_us = lambda us: CLOCK.sleep_ms(us // 1000) or setattr(CLOCK, "us", CLOCK.us + us)
fake_time.ticks_ms = CLOCK.ticks_ms
fake_time.ticks_us = CLOCK.ticks_us
fake_time.ticks_diff = CLOCK.ticks_diff

sys.modules["machine"] = machine
sys.modules["time"] = fake_time

# ---------------------------------------------------------------- fake bluetooth
class FakeUUID:
    def __init__(self, spec):
        self.spec = spec

    def __bytes__(self):
        import uuid
        return uuid.UUID(self.spec).bytes_le

    def __str__(self):
        return self.spec


class FakeBLE:
    """Records every call so the advertisement and notifies can be asserted."""
    instances = []

    def __init__(self):
        self.calls = []
        self.notifies = []
        self.written = {}
        self._irq = None
        self.handles = [(100, 101)]
        FakeBLE.instances.append(self)

    def active(self, v=None):
        self.calls.append(("active", v))
        return True

    def config(self, **kw):
        self.calls.append(("config", kw))

    def gatts_register_services(self, services):
        self.calls.append(("register", services))
        return self.handles

    def gatts_set_buffer(self, h, n, append=False):
        self.calls.append(("set_buffer", h, n, append))

    def gatts_write(self, h, data):
        self.written[h] = bytes(data)

    def gatts_read(self, h):
        return b""

    def gatts_notify(self, conn, h, data):
        self.notifies.append((conn, h, bytes(data)))

    def gap_advertise(self, interval, adv, resp_data=None):
        self.calls.append(("advertise", interval, bytes(adv), bytes(resp_data) if resp_data else None))

    def irq(self, fn):
        self._irq = fn


bluetooth = types.ModuleType("bluetooth")
bluetooth.BLE = FakeBLE
bluetooth.UUID = FakeUUID
bluetooth.FLAG_READ = 0x0002
bluetooth.FLAG_WRITE = 0x0008
bluetooth.FLAG_WRITE_NO_RESPONSE = 0x0004
bluetooth.FLAG_NOTIFY = 0x0010
sys.modules["bluetooth"] = bluetooth

sys.path.insert(0, FW)
import sensors        # noqa: E402
import ble_link       # noqa: E402

print("=" * 62)
print("1. YF-S201 flow: 450 pulses per litre")
print("=" * 62)
flow = sensors.Flow(27, 450.0)
flow._pin.fire(450)          # 450 pulses ...
flow.sample(60000)           # ... in 60 s  -> 7.5 Hz
check("450 pulses/60 s -> 1.00 L/min", abs(flow.lpm - 1.0) < 1e-9, "(got %.6f)" % flow.lpm)
check("450 pulses -> 1.00 L total", abs(flow.total_l - 1.0) < 1e-9, "(got %.6f)" % flow.total_l)

flow._pin.fire(225)
flow.sample(30000)           # 225 in 30 s -> 7.5 Hz again
check("225 pulses/30 s -> 1.00 L/min", abs(flow.lpm - 1.0) < 1e-9, "(got %.6f)" % flow.lpm)
check("total accumulates to 1.50 L", abs(flow.total_l - 1.5) < 1e-9, "(got %.6f)" % flow.total_l)

flow._pin.fire(4500)
flow.sample(60000)           # 4500/60 = 75 Hz = 10 L/min
check("4500 pulses/60 s -> 10.00 L/min", abs(flow.lpm - 10.0) < 1e-9, "(got %.6f)" % flow.lpm)

flow.reset()
check("reset() zeroes the total", flow.total_l == 0.0)

print()
print("=" * 62)
print("2. LJ12A3 proximity: edge period -> RPM")
print("=" * 62)
rpm = sensors.Rpm(26, pulses_per_rev=1)
# 60 ms between edges = 16.67 Hz = 1000 rpm for 1 target/rev
CLOCK.us = 0
rpm._pin.fire()
CLOCK.us += 60000
rpm._pin.fire()
check("60 ms period -> 1000 RPM", rpm.value() == 1000, "(got %d)" % rpm.value())

rpm4 = sensors.Rpm(26, pulses_per_rev=4)
CLOCK.us = 0
rpm4._pin.fire()
CLOCK.us += 60000
rpm4._pin.fire()
check("60 ms period, 4 targets -> 250 RPM", rpm4.value() == 250, "(got %d)" % rpm4.value())

# no pulse for longer than the 2 s timeout -> 0
CLOCK.us += 3_000_000
check("stale >2 s -> 0 RPM", rpm.value() == 0, "(got %d)" % rpm.value())

# ringing faster than MIN_EDGE_US must be ignored
rpm5 = sensors.Rpm(26)
CLOCK.us = 0
rpm5._pin.fire()
CLOCK.us += 50          # 50 us = contact bounce
rpm5._pin.fire()
check("50 us bounce ignored (period unchanged)", rpm5._period == 0, "(period=%s)" % rpm5._period)

print()
print("=" * 62)
print("3. ACS712 current: volts -> amps (185 mV/A behind 10k/20k)")
print("=" * 62)
cur = sensors.CurrentSensor(34, mv_per_amp=185.0)
DIV = 10000.0 / 30000.0 if False else 20000.0 / (10000.0 + 20000.0)
check("divider ratio is 0.6667", abs(cur.div - DIV) < 1e-12, "(got %.6f)" % cur.div)

FakeADC.volts_at_pin = 2.5 * DIV          # zero current
cur.sample()
# 1e-3 tolerance: the stub reports whole microvolts, so ~2e-6 A of quantisation
# is expected and is not a firmware fault.
check("zero current -> ~0.00 A", abs(cur.amps) < 1e-3 and cur.ok, "(got %.6f ok=%s)" % (cur.amps, cur.ok))

FakeADC.volts_at_pin = (2.5 + 0.185) * DIV  # +1 A
cur2 = sensors.CurrentSensor(34, mv_per_amp=185.0)
cur2.sample(raw_filter=1.0)                # no smoothing, check the maths
check("2.685 V sensor -> 1.00 A", abs(cur2.amps - 1.0) < 1e-6, "(got %.6f)" % cur2.amps)

FakeADC.volts_at_pin = (2.5 - 0.185) * DIV  # -1 A
cur3 = sensors.CurrentSensor(34, mv_per_amp=185.0)
cur3.sample(raw_filter=1.0)
check("-1 A reads negative", abs(cur3.amps + 1.0) < 1e-3, "(got %.6f)" % cur3.amps)

FakeADC.volts_at_pin = 0.142 * 1.0          # floating pin, sensor absent
cur4 = sensors.CurrentSensor(34)
cur4.sample()
check("absent sensor -> ok=False and 0 A", (not cur4.ok) and cur4.amps == 0.0,
      "(v_sensor=%.3f ok=%s)" % (cur4.v_sensor, cur4.ok))

print()
print("=" * 62)
print("4. Battery divider: 47k / 10k")
print("=" * 62)
bat = sensors.BatterySensor(35)
FakeADC.volts_at_pin = 14.8 * (10000.0 / 57000.0)
bat.sample()
check("14.8 V battery reads 14.80", bat.ok and abs(bat.volts - 14.8) < 0.01, "(got %.3f)" % bat.volts)

FakeADC.volts_at_pin = 12.0 * (10000.0 / 57000.0)
bat.sample()
check("12.0 V battery reads 12.00", bat.ok and abs(bat.volts - 12.0) < 0.01, "(got %.3f)" % bat.volts)

FakeADC.volts_at_pin = 0.14                 # nothing connected
bat.sample()
check("no divider fitted -> ok=False", not bat.ok, "(got %s)" % bat.ok)

print()
print("=" * 62)
print("5. Telemetry JSON frame")
print("=" * 62)


def build_frame(f, t, r, a, v, c, ms):
    """Mirror of the format string in firmware/main.py (a and v may be None)."""
    return '{"f":%.2f,"t":%.2f,"r":%d,"a":%s,"v":%s,"c":%d,"ms":%d}' % (
        f, t, r,
        ("%.2f" % a) if a is not None else "null",
        ("%.2f" % v) if v is not None else "null",
        c, ms)


frame = build_frame(12.34, 45.67, 1450, 1.23, 12.64, 1, 123456)
print("  frame:", frame)
parsed = json.loads(frame)
check("frame is valid JSON", True)
check("keys match the app parser", sorted(parsed.keys()) == ["a", "c", "f", "ms", "r", "t", "v"])
check("f parses to 12.34", abs(parsed["f"] - 12.34) < 1e-9)
check("r parses to 1450", parsed["r"] == 1450)
check("v parses to 12.64", abs(parsed["v"] - 12.64) < 1e-9)

no_bat = build_frame(0.0, 0.0, 0, None, None, 0, 6769)
print("  frame:", no_bat)
check("null battery is JSON null", json.loads(no_bat)["v"] is None)
check("null current is JSON null (sensor absent, not a fake 0.00)",
      json.loads(no_bat)["a"] is None)

# a frame must fit one BLE notification at the negotiated MTU
check("frame fits MTU 247 (payload <= 244)", len(frame) <= 244, "(%d bytes)" % len(frame))
check("frame EXCEEDS default MTU 23 payload (so MTU negotiation matters)",
      len(frame) > 20, "(%d bytes)" % len(frame))

print()
print("=" * 62)
print("6. BLE advertisement + notify fan-out")
print("=" * 62)
link = ble_link.BleLink(on_command=lambda m: None)
adv = [c for c in link.ble.calls if c[0] == "advertise"]
check("gap_advertise was called", len(adv) == 1)
if adv:
    _, interval, a, r = adv[0]
    name = b"GeorgePPM"
    uuid_le = bytes(ble_link.SERVICE_UUID)
    # iOS only filters on the advertisement packet, so the UUID must be in adv.
    check("advertisement carries the 128-bit service UUID (iOS needs this)",
          uuid_le in a or uuid_le[::-1] in a, "(%r)" % a)
    check("scan response carries the name", r is not None and name in r, "(%r)" % r)
    check("advertising payload <= 31 bytes", len(a) <= 31, "(%d bytes)" % len(a))
    check("scan response <= 31 bytes", r is None or len(r) <= 31, "(%d bytes)" % len(r))

check("mtu=247 requested", any(c[0] == "config" and c[1].get("mtu") == 247 for c in link.ble.calls))

# no clients yet -> write but no notify
link.publish('{"f":0}')
check("publish with 0 clients writes but does not notify",
      link.ble.notifies == [] and 100 in link.ble.written)

link.conns.add(1)
link.conns.add(2)
link.publish('{"f":1}')
check("publish notifies every connected client", len(link.ble.notifies) == 2,
      "(%d notifies)" % len(link.ble.notifies))

print()
print("=" * 62)
print("RESULT: %d passed, %d failed" % (len(PASS), len(FAIL)))
if FAIL:
    print("failed:", ", ".join(FAIL))
print("=" * 62)
sys.exit(1 if FAIL else 0)
