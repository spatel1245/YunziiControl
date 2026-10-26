"""30 s live-frame test: animate the 4 LEDs under the decal, keep the rest white. Nothing is stored."""
import os
HERE = os.path.dirname(os.path.abspath(__file__))
import sys, time, colorsys; sys.path.insert(0, HERE)
import iokit_hid as h
DECAL = [15*6+0, 16*6+0, 17*6+0, 18*6+0]  # Home, End, PgUp, PgDn
dev = h.require()
def frame(colours):
    p = bytearray(520); p[0:8] = bytes([0x06, 0x08, 0x00, 0x00, 0x01, 0x00, 0x7a, 0x01])
    for i, (r, g, b) in enumerate(colours): p[8+i*3:11+i*3] = bytes([r, g, b])
    return h.set_feature(dev, p)
t0 = time.time(); errs = 0; n = 0
while time.time() - t0 < 30:
    t = time.time() - t0
    c = [(255, 255, 255)] * 126
    if t < 18:
        col = [(255, 0, 0), (0, 255, 0), (0, 0, 255)][int(t // 6)]
        for i in DECAL: c[i] = col
    else:
        for k, i in enumerate(DECAL):
            r, g, b = colorsys.hsv_to_rgb(((t * 0.5) + k * 0.15) % 1, 1, 1); c[i] = (int(r*255), int(g*255), int(b*255))
    if frame(c): errs += 1
    n += 1; time.sleep(0.05)
print(f"sent {n} frames, {errs} errors")
