"""Set one key-table entry. Usage: setkey.py LAYER INDEX HEX8   e.g. setkey.py 1 18 0200029f  (Fn+F3 -> Mission Control)
Reads the layer, refuses to touch the Fn key (index 59), writes, and verifies."""
import os
HERE = os.path.dirname(os.path.abspath(__file__))
import sys, time; sys.path.insert(0, HERE)
import iokit_hid as h
layer, idx, code = int(sys.argv[1]), int(sys.argv[2]), bytes.fromhex(sys.argv[3])
assert len(code) == 4 and idx != 59 and 0 <= idx < 128 and 0 <= layer < 4
dev = h.require()
def xfer(cmd, sub, data=None, ln=512):
    p = bytearray(520); p[0:8] = bytes([0x06, cmd if data else cmd | 0x80, sub, 0, 1, 0, ln & 0xff, ln >> 8])
    if data: p[8:8 + ln] = data
    time.sleep(0.02); assert h.set_feature(dev, p) == 0; time.sleep(0.02)
    if data: return
    r, resp = h.get_feature(dev, 0x06, 520); assert r == 0; return bytearray(resp[8:8 + ln])
t = xfer(0x03, layer)
print(f"layer {layer} index {idx}: {t[idx*4:idx*4+4].hex()} -> {code.hex()}")
t[idx*4:idx*4+4] = code
xfer(0x03, layer, bytes(t)); time.sleep(0.05)
assert xfer(0x03, layer) == t, "read-back mismatch"
print("saved")
