# ble_link.py - BLE GATT server for George PPM telemetry
#
# Service  4a5b6c7d-0001-4d8e-9f00-a1b2c3d4e5f6
#   char   4a5b6c7d-0002-...  READ + NOTIFY   telemetry JSON
#   char   4a5b6c7d-0003-...  WRITE           commands: RESET / ZERO / PING
import bluetooth
import struct

_IRQ_CENTRAL_CONNECT = getattr(bluetooth, "_IRQ_CENTRAL_CONNECT", 1)
_IRQ_CENTRAL_DISCONNECT = getattr(bluetooth, "_IRQ_CENTRAL_DISCONNECT", 2)
_IRQ_GATTS_WRITE = getattr(bluetooth, "_IRQ_GATTS_WRITE", 3)

SERVICE_UUID = bluetooth.UUID("4a5b6c7d-0001-4d8e-9f00-a1b2c3d4e5f6")
TELEM_UUID = bluetooth.UUID("4a5b6c7d-0002-4d8e-9f00-a1b2c3d4e5f6")
CMD_UUID = bluetooth.UUID("4a5b6c7d-0003-4d8e-9f00-a1b2c3d4e5f6")

_NAME = "GeorgePPM"


class BleLink:
    def __init__(self, on_command=None, mtu=247):
        self.conns = set()
        self.on_command = on_command
        self.ble = bluetooth.BLE()
        self.ble.active(True)
        try:
            self.ble.config(gap_name=_NAME)
        except Exception:
            pass
        try:
            self.ble.config(mtu=mtu)
        except Exception:
            pass

        telem = (TELEM_UUID, bluetooth.FLAG_READ | bluetooth.FLAG_NOTIFY)
        cmd = (CMD_UUID, bluetooth.FLAG_WRITE | bluetooth.FLAG_WRITE_NO_RESPONSE)
        service = (SERVICE_UUID, (telem, cmd))
        ((self.h_telem, self.h_cmd),) = self.ble.gatts_register_services((service,))
        try:
            self.ble.gatts_set_buffer(self.h_cmd, 64, True)   # append mode
        except Exception:
            pass
        self.ble.gatts_write(self.h_telem, b'{"boot":1}')
        self.ble.irq(self._irq)
        self._advertise()

    # ---------------------------------------------------------- internals
    def _advertise(self):
        # Layout matters for iOS: CoreBluetooth filters scans on the ADVERTISEMENT
        # packet, so the 128-bit service UUID goes there. The name rides in the
        # scan response (iOS exposes it as CBAdvertisementDataLocalNameKey).
        # adv = flags(3) + UUID list(18) = 21 bytes, resp = name(11) bytes.
        name = _NAME.encode()
        adv = bytearray()
        adv += struct.pack("BBB", 2, 0x01, 0x06)          # flags: LE only, discoverable
        adv += struct.pack("BB", 17, 0x07) + bytes(SERVICE_UUID)   # 128-bit UUID list
        resp = bytearray()
        resp += struct.pack("BB", len(name) + 1, 0x09) + name
        try:
            self.ble.gap_advertise(200000, adv, resp_data=resp)
        except Exception:
            try:
                self.ble.gap_advertise(200000, adv)
            except Exception as e:
                print("advertise failed:", e)

    def _irq(self, event, data):
        if event == _IRQ_CENTRAL_CONNECT:
            self.conns.add(data[0])
        elif event == _IRQ_CENTRAL_DISCONNECT:
            self.conns.discard(data[0])
            self._advertise()
        elif event == _IRQ_GATTS_WRITE:
            conn, attr = data[0], data[1]
            if attr == self.h_cmd and self.on_command:
                try:
                    msg = self.ble.gatts_read(self.h_cmd).decode().strip()
                except Exception:
                    return
                if msg:
                    self.on_command(msg)

    # ---------------------------------------------------------- public
    def connected(self):
        return len(self.conns)

    def publish(self, payload):
        if isinstance(payload, str):
            payload = payload.encode()
        try:
            self.ble.gatts_write(self.h_telem, payload)
        except Exception as e:
            print("gatts_write:", e)
            return
        for c in list(self.conns):
            try:
                self.ble.gatts_notify(c, self.h_telem, payload)
            except Exception as e:
                print("notify:", e)
