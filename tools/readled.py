import os
HERE = os.path.dirname(os.path.abspath(__file__))
import sys, time; sys.path.insert(0, HERE)
import iokit_hid as h
dev = h.require()
hdr = bytearray(520); hdr[0:8] = bytes([0x06, 0x84, 0x00, 0x00, 0x01, 0x00, 0x80, 0x00])
time.sleep(0.02); print("set ->", hex(h.set_feature(dev, hdr) & 0xffffffff)); time.sleep(0.02)
r, resp = h.get_feature(dev, 0x06, 520)
print("get ->", hex(r & 0xffffffff), "len", len(resp), "hdr", resp[:8].hex(" "))
b = resp[8:8+128]
for i in range(0, len(b), 16): print(f"{i:02x}: " + " ".join(f"{x:02x}" for x in b[i:i+16]))
if len(b) == 128:
    print("valid trailer 5a a5:", b[126] == 0x5a and b[127] == 0xa5)
    print("mode byte[9]", b[9], "effect byte[10]", b[10])
    open(os.path.join(HERE, f"led_block_backup_{int(time.time())}.bin"), "wb").write(b)
