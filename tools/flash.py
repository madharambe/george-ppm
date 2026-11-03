#!/usr/bin/env python3
"""flash.py - push every .py in firmware/ to the MicroPython ESP32 over serial.

Usage:
    python tools/flash.py [COM10]

Works around this board's missing DTR/RTS auto-reset: it interrupts whatever is
running, enters the raw REPL, and writes each file as base64 so quoting can
never corrupt the transfer. Finally it soft-reboots so main.py starts.
"""
import base64
import os
import sys
import time

import serial

PORT = sys.argv[1] if len(sys.argv) > 1 else "COM10"
HERE = os.path.dirname(os.path.abspath(__file__))
FW = os.path.normpath(os.path.join(HERE, "..", "firmware"))


def read_until(ser, token, timeout):
    buf = b""
    t = time.time()
    while time.time() - t < timeout:
        buf += ser.read(512)
        if token in buf:
            return buf, True
    return buf, False


def drain(ser, secs=0.4):
    t = time.time()
    while time.time() - t < secs:
        ser.read(4096)


def stop_running(ser):
    for _ in range(4):
        ser.write(b"\x03")
        time.sleep(0.25)
        drain(ser, 0.2)
    drain(ser, 0.4)


def enter_raw(ser):
    ser.write(b"\x01")
    if read_until(ser, b"raw REPL; CTRL-B to exit", 4)[1]:
        return True
    drain(ser, 1.0)
    ser.write(b"\x01")
    return read_until(ser, b"raw REPL; CTRL-B to exit", 4)[1]


def run(ser, code, timeout=30):
    if not enter_raw(ser):
        raise RuntimeError("cannot enter raw REPL")
    time.sleep(0.1)
    ser.write(code.encode() + b"\x04")
    out = read_until(ser, b"\x04", timeout)[0]
    err = read_until(ser, b"\x04", 12)[0]
    read_until(ser, b">", 4)
    ser.write(b"\x02")
    time.sleep(0.15)
    drain(ser, 0.3)
    o = out.decode("utf-8", "replace")
    if o.startswith("OK"):
        o = o[2:]
    return o.strip(), err.decode("utf-8", "replace").strip()


def boot_output(ser, secs=6.0):
    buf = b""
    t = time.time()
    while time.time() - t < secs:
        buf += ser.read(4096)
    return buf.decode("utf-8", "replace").strip()[-900:]


def main():
    files = sorted(f for f in os.listdir(FW) if f.endswith(".py"))
    if not files:
        print("no .py files in", FW)
        return 1
    print("port:", PORT)
    print("files:", ", ".join(files))
    ser = serial.Serial(PORT, 115200, timeout=0.1, write_timeout=3)
    ser.dtr = False
    ser.rts = False
    try:
        stop_running(ser)
        for name in files:
            with open(os.path.join(FW, name), "rb") as fh:
                blob = fh.read()
            b64 = base64.b64encode(blob).decode()
            code = "import binascii, os\nf=open('%s','wb')\n" % name
            for i in range(0, len(b64), 400):
                code += "f.write(binascii.a2b_base64(b'%s'))\n" % b64[i:i + 400]
            code += "f.close()\nprint('%s', os.stat('%s')[6])\n" % (name, name)
            out, err = run(ser, code)
            last = out.splitlines()[-1] if out else "(no output)"
            print("  %-16s %s%s" % (name, last, ("  ERR: " + err) if err else ""))
        ser.write(b"\x04")           # soft reboot -> main.py runs
        print("\n--- boot output ---")
        print(boot_output(ser))
    finally:
        ser.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
