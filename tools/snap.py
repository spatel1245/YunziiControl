"""Snapshot every readable area into snaps/<name>/ and diff against another snapshot if given."""
import os
HERE = os.path.dirname(os.path.abspath(__file__))
import sys, os, time; sys.path.insert(0, HERE)
import iokit_hid as h
name = sys.argv[1]
dev = h.require()
def read(cmd, sub, ln):
    total = -(-ln // 512); out = b""
    for i in range(total):
        size = min(512, ln - i * 512)
        hdr = bytearray(520); hdr[0:8] = bytes([0x06, cmd | 0x80, sub, 0, total, i, size & 0xff, size >> 8])
        time.sleep(0.02); assert h.set_feature(dev, hdr) == 0; time.sleep(0.02)
        r, resp = h.get_feature(dev, 0x06, 520); assert r == 0
        out += resp[8:8 + size]
    return out
areas = {"model": (0x02, 1, 6), "led": (0x04, 0, 128)}
for l in range(4): areas[f"keymap{l}"] = (0x03, l, 512)
for g in range(2): areas[f"perkey{g}"] = (0x06, g, 384)
areas["rgbtable"] = (0x0a, 0, 512)
d = os.path.join(HERE, "snaps", name); os.makedirs(d, exist_ok=True)
for k, (c, s, n) in areas.items(): open(f"{d}/{k}.bin", "wb").write(read(c, s, n))
print("saved", d)
if len(sys.argv) > 2:
    o = os.path.join(HERE, "snaps", sys.argv[2])
    for k in areas:
        a, b = open(f"{o}/{k}.bin", "rb").read(), open(f"{d}/{k}.bin", "rb").read()
        diffs = [(i, a[i], b[i]) for i in range(len(a)) if a[i] != b[i]]
        if diffs: print(k, [(hex(i), f"{x:02x}->{y:02x}") for i, x, y in diffs[:40]])
    print("diff done")
