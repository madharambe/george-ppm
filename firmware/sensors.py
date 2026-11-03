# sensors.py - George PPM sensor drivers
#
#   YF-S201 flow      -> GPIO27  (VCC 5V, signal via 1k/2k divider)
#   LJ12A3-4-Z/BX     -> GPIO26  (VCC 12V, NPN open collector, 10k pull-up to 3V3)
#   ACS712 current    -> GPIO34  (VCC 5V, OUT via 10k/20k divider)  ADC1_CH6
#   Battery divider   -> GPIO35  (47k series + 10k to GND)          ADC1_CH7
import time
from machine import Pin, ADC

# ---------------------------------------------------------------- flow
class Flow:
    """YF-S201: ~450 pulses per litre."""

    def __init__(self, pin_no, pulses_per_litre=450.0):
        self.ppl = pulses_per_litre
        self.total_l = 0.0
        self.lpm = 0.0
        self._n = 0
        self._pin = Pin(pin_no, Pin.IN, Pin.PULL_UP)
        self._pin.irq(trigger=Pin.IRQ_RISING, handler=self._isr)

    def _isr(self, p):
        self._n += 1

    def sample(self, dt_ms):
        n = self._n
        self._n = 0
        if dt_ms > 0:
            hz = n * 1000.0 / dt_ms
            self.lpm = hz * 60.0 / self.ppl
        self.total_l += n / self.ppl
        return self.lpm

    def reset(self):
        self.total_l = 0.0


# ---------------------------------------------------------------- rpm
class Rpm:
    """Inductive proximity switch: NPN open collector, one pulse per target."""

    def __init__(self, pin_no, pulses_per_rev=1, timeout_us=2000000, min_edge_us=300):
        self.ppr = pulses_per_rev
        self.timeout_us = timeout_us
        self.min_edge_us = min_edge_us
        self._last = 0
        self._period = 0
        self._pin = Pin(pin_no, Pin.IN, Pin.PULL_UP)
        self._pin.irq(trigger=Pin.IRQ_FALLING, handler=self._isr)

    def _isr(self, p):
        now = time.ticks_us()
        if self._last:
            d = time.ticks_diff(now, self._last)
            if d >= self.min_edge_us:
                self._period = d
        self._last = now

    def value(self):
        if not self._period or not self._last:
            return 0
        if time.ticks_diff(time.ticks_us(), self._last) > self.timeout_us:
            return 0
        return int(60.0 * 1000000.0 / (self._period * self.ppr))


# ---------------------------------------------------------------- adc
class Analog:
    """Voltage at an ADC pin. read_uv() is calibrated; read() is the fallback."""

    def __init__(self, pin_no):
        self.a = ADC(Pin(pin_no))
        try:
            self.a.atten(ADC.ATTN_11DB)
            self.a.width(ADC.WIDTH_12BIT)
        except Exception:
            pass

    def volts(self, n=24):
        try:
            t = 0
            for _ in range(n):
                t += self.a.read_uv()
            return (t / n) / 1000000.0
        except Exception:
            t = 0
            for _ in range(n):
                t += self.a.read()
            return (t / n) / 4095.0 * 3.3


class CurrentSensor:
    """ACS712 behind a resistor divider."""

    def __init__(self, pin_no, mv_per_amp=185.0, r1=10000.0, r2=20000.0,
                 v_zero=2.5, valid_lo=1.0, valid_hi=4.0):
        self.adc = Analog(pin_no)
        self.mv_per_amp = mv_per_amp
        self.div = r2 / (r1 + r2)
        self.v_zero = v_zero
        self.valid_lo = valid_lo
        self.valid_hi = valid_hi
        self.amps = 0.0
        self.ok = False
        self.v_sensor = 0.0

    def sample(self, raw_filter=0.4):
        self.v_sensor = self.adc.volts() / self.div
        self.ok = self.valid_lo <= self.v_sensor <= self.valid_hi
        if self.ok:
            a = (self.v_sensor - self.v_zero) / (self.mv_per_amp / 1000.0)
            self.amps += (a - self.amps) * raw_filter
        else:
            self.amps = 0.0
        return self.amps

    def autozero(self, samples=20):
        acc = 0.0
        for _ in range(samples):
            acc += self.adc.volts(16)
            time.sleep_ms(20)
        v = (acc / samples) / self.div
        if self.valid_lo <= v <= self.valid_hi:
            self.v_zero = v
            return True, v
        return False, v


class BatterySensor:
    """12 V lead-acid through a resistor divider."""

    def __init__(self, pin_no, r1=47000.0, r2=10000.0, min_v=5.0):
        self.adc = Analog(pin_no)
        self.div = r2 / (r1 + r2)
        self.min_v = min_v
        self.volts = 0.0
        self.ok = False

    def sample(self):
        v = self.adc.volts() / self.div
        self.ok = v >= self.min_v
        self.volts = v if self.ok else 0.0
        return self.volts
