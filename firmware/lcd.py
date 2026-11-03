# lcd.py - HD44780 character LCD over a PCF8574 I2C backpack
# Board: ESP32-D0WD-V3 | SCL=GPIO18 SDA=GPIO19 | addr 0x27
# Backpack pinout: P0=RS P1=RW P2=E P3=backlight P4-P7=D4-D7
import time


class Lcd:
    ROW_OFFSET = (0x00, 0x40, 0x14, 0x54)

    def __init__(self, i2c, addr=0x27, cols=16, rows=2):
        self.i2c = i2c
        self.addr = addr
        self.cols = cols
        self.rows = rows
        self.bl = 0x08
        time.sleep_ms(60)
        for _ in range(3):          # force 8-bit x3, then switch to 4-bit
            self._nib(0x03, 0)
            time.sleep_ms(6)
        self._nib(0x02, 0)
        time.sleep_ms(2)
        self.cmd(0x28)              # 4-bit, 2 lines, 5x8
        self.cmd(0x08)              # display off
        self.cmd(0x01)              # clear
        time.sleep_ms(3)
        self.cmd(0x0C)              # display on, cursor off
        self.cmd(0x06)              # entry mode: increment

    def _w(self, b):
        self.i2c.writeto(self.addr, bytes([b & 0xFF]))

    def _nib(self, nib, rs):
        base = self.bl | ((nib & 0x0F) << 4) | (0x01 if rs else 0x00)
        self._w(base)
        time.sleep_us(20)
        self._w(base | 0x04)        # E high
        time.sleep_us(40)
        self._w(base & ~0x04)       # E low -> latch
        time.sleep_us(40)

    def cmd(self, c):
        self._nib((c >> 4) & 0x0F, 0)
        self._nib(c & 0x0F, 0)
        time.sleep_us(60)

    def data(self, c):
        self._nib((c >> 4) & 0x0F, 1)
        self._nib(c & 0x0F, 1)
        time.sleep_us(60)

    def clear(self):
        self.cmd(0x01)
        time.sleep_ms(3)

    def backlight(self, on=True):
        self.bl = 0x08 if on else 0x00
        self._w(self.bl)

    def move(self, col, row):
        self.cmd(0x80 | (col + self.ROW_OFFSET[row % 4]))

    def putstr(self, s):
        for ch in str(s):
            self.data(ord(ch))

    def text(self, s, col=0, row=0):
        self.move(col, row)
        self.putstr(str(s)[:max(0, self.cols - col)])
