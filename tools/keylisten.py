"""Print top-row style output from the YZ98 for N seconds (default 60): media codes, F-keys, and shortcut combos.
Ordinary typing (letters, digits, punctuation, Enter, Backspace, plain arrows) is never printed. Usage: keylisten.py [seconds]"""
import os
HERE = os.path.dirname(os.path.abspath(__file__))
import ctypes, sys, time
from ctypes import c_void_p, c_int32, c_uint32, c_long, c_double, CFUNCTYPE, byref
sys.path.insert(0, HERE)
import iokit_hid as h
io, cf = h.iokit, h.cf
for name, res, args in [("IOHIDValueGetElement", c_void_p, [c_void_p]), ("IOHIDValueGetIntegerValue", c_long, [c_void_p]),
                        ("IOHIDElementGetUsagePage", c_uint32, [c_void_p]), ("IOHIDElementGetUsage", c_uint32, [c_void_p])]:
    getattr(io, name).restype = res; getattr(io, name).argtypes = args
io.IOHIDDeviceRegisterInputValueCallback.argtypes = [c_void_p, c_void_p, c_void_p]
io.IOHIDDeviceScheduleWithRunLoop.argtypes = [c_void_p, c_void_p, c_void_p]
cf.CFRunLoopGetCurrent.restype = c_void_p
cf.CFRunLoopRunInMode.argtypes = [c_void_p, c_double, ctypes.c_bool]
mode = c_void_p.in_dll(cf, "kCFRunLoopDefaultMode")
PAGES = {0x07: "Keyboard", 0x0C: "Consumer", 0x01: "GenericDesktop", 0xFF: "AppleVendorTopCase", 0xFF01: "AppleVendorKeyboard"}
seen = {}
CB = CFUNCTYPE(None, c_void_p, c_int32, c_void_p, c_void_p)
MODS = {0xE0: "Ctrl", 0xE1: "Shift", 0xE2: "Opt", 0xE3: "Cmd", 0xE4: "RCtrl", 0xE5: "RShift", 0xE6: "ROpt", 0xE7: "RCmd"}
FKEYS = set(range(0x3A, 0x46)) | set(range(0x68, 0x74))
held = set()
recent = []   # (time, usage) of non-alphanumeric key presses; the keyboard can report the key before its modifier
def cb(ctx, result, sender, value):
    el = io.IOHIDValueGetElement(value)
    page, usage, v = io.IOHIDElementGetUsagePage(el), io.IOHIDElementGetUsage(el), io.IOHIDValueGetIntegerValue(value)
    now = time.time(); stamp = time.strftime('%H:%M:%S')
    if page == 0x07 and usage in MODS:
        (held.add if v else held.discard)(usage)
        if v and usage not in (0xE1, 0xE5):
            for t, k in recent:
                if now - t < 0.05: print(f"{stamp} combo {MODS[usage]}+0x{k:02X}", flush=True)
            recent.clear()
        return
    if not v or usage >= 0x10000: return
    if page == 0x0C and usage:
        print(f"{stamp} media 0x{usage:03X}", flush=True)
    elif page in (0xFF, 0xFF01):
        print(f"{stamp} apple-vendor 0x{usage:02X}", flush=True)
    elif page == 0x07 and usage in FKEYS:
        print(f"{stamp} key F{usage - 0x39 if usage < 0x46 else usage - 0x5B}" + (" with " + "+".join(MODS[m] for m in sorted(held)) if held else ""), flush=True)
    elif page == 0x07 and not (0x04 <= usage <= 0x27):
        if held - {0xE1, 0xE5}:
            print(f"{stamp} combo {'+'.join(MODS[m] for m in sorted(held))}+0x{usage:02X}", flush=True)
        else:
            recent[:] = [(t, k) for t, k in recent if now - t < 0.05] + [(now, usage)]
cbp = CB(cb)
# match every interface of the keyboard (VID/PID only)
mgr = io.IOHIDManagerCreate(None, 0)
d = cf.CFDictionaryCreateMutable(None, 0, byref(h.kCFTypeDictionaryKeyCallBacks), byref(h.kCFTypeDictionaryValueCallBacks))
for k, v in (("VendorID", 0x258a), ("ProductID", 0x010c)): cf.CFDictionarySetValue(d, h._s(k), h._n(v))
io.IOHIDManagerSetDeviceMatching(mgr, d)
s = io.IOHIDManagerCopyDevices(mgr)
n = cf.CFSetGetCount(s) if s else 0
arr = (c_void_p * n)(); n and cf.CFSetGetValues(s, arr)
print("listening on", n, "keyboard interfaces", flush=True)
for dev in arr:
    if h.open_dev(dev) == 0:
        io.IOHIDDeviceRegisterInputValueCallback(dev, cbp, None)
        io.IOHIDDeviceScheduleWithRunLoop(dev, cf.CFRunLoopGetCurrent(), mode)
cf.CFRunLoopRunInMode(mode, float(sys.argv[1]) if len(sys.argv) > 1 else 60, False)
print("done", flush=True)
