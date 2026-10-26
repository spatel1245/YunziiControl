"""Read LED block, set Fixed On / white, write back, verify. Usage: writeled.py [restore.bin]"""
import os
HERE = os.path.dirname(os.path.abspath(__file__))
import sys, time; sys.path.insert(0, HERE)
import iokit_hid as h

def read_block(dev):
    hdr = bytearray(520); hdr[0:8] = bytes([0x06, 0x84, 0, 0, 1, 0, 0x80, 0])
    time.sleep(0.02); assert h.set_feature(dev, hdr) == 0; time.sleep(0.02)
    r, resp = h.get_feature(dev, 0x06, 520)
    assert r == 0 and len(resp) >= 136, (hex(r & 0xffffffff), len(resp))
    b = bytearray(resp[8:136])
    assert b[126] == 0x5a and b[127] == 0xa5, "invalid block trailer"
    return b

def write_block(dev, b):
    pk = bytearray(520); pk[0:8] = bytes([0x06, 0x04, 0, 0, 1, 0, 0x80, 0]); pk[8:136] = b
    for _ in range(3):
        time.sleep(0.02)
        if h.set_feature(dev, pk) == 0: return
        time.sleep(0.07)
    raise RuntimeError("write failed")

dev = h.require()
cur = read_block(dev)
if len(sys.argv) > 1:
    new = bytearray(open(sys.argv[1], "rb").read()); assert len(new) == 128
else:
    new = bytearray(cur)
    new[9] = 0; new[10] = 1                       # Fixed On
    new[0x3b] = (new[0x3b] & 0xf0) | 0x06         # colour nibble -> white, keep speed
write_block(dev, new)
time.sleep(0.1)
back = read_block(dev)
print("changed:", [(hex(i), hex(cur[i]), hex(new[i])) for i in range(128) if cur[i] != new[i]])
print("verified:", back == new, "| effect", back[10], "slot0", back[0x3a:0x3c].hex(" "))
