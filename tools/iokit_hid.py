"""Minimal IOKit HID access via ctypes (non-exclusive open, feature reports)."""
import ctypes, ctypes.util
from ctypes import c_void_p, c_int32, c_uint32, c_long, c_char_p, POINTER, byref, c_uint8

iokit = ctypes.cdll.LoadLibrary(ctypes.util.find_library("IOKit"))
cf = ctypes.cdll.LoadLibrary(ctypes.util.find_library("CoreFoundation"))

cf.CFStringCreateWithCString.restype = c_void_p
cf.CFStringCreateWithCString.argtypes = [c_void_p, c_char_p, c_uint32]
cf.CFNumberCreate.restype = c_void_p
cf.CFNumberCreate.argtypes = [c_void_p, c_long, c_void_p]
cf.CFNumberGetValue.argtypes = [c_void_p, c_long, c_void_p]
cf.CFDictionaryCreateMutable.restype = c_void_p
cf.CFDictionaryCreateMutable.argtypes = [c_void_p, c_long, c_void_p, c_void_p]
cf.CFDictionarySetValue.argtypes = [c_void_p, c_void_p, c_void_p]
cf.CFSetGetCount.restype = c_long
cf.CFSetGetCount.argtypes = [c_void_p]
cf.CFSetGetValues.argtypes = [c_void_p, POINTER(c_void_p)]
kCFTypeDictionaryKeyCallBacks = c_void_p.in_dll(cf, "kCFTypeDictionaryKeyCallBacks")
kCFTypeDictionaryValueCallBacks = c_void_p.in_dll(cf, "kCFTypeDictionaryValueCallBacks")

iokit.IOHIDManagerCreate.restype = c_void_p
iokit.IOHIDManagerCreate.argtypes = [c_void_p, c_uint32]
iokit.IOHIDManagerSetDeviceMatching.argtypes = [c_void_p, c_void_p]
iokit.IOHIDManagerCopyDevices.restype = c_void_p
iokit.IOHIDManagerCopyDevices.argtypes = [c_void_p]
iokit.IOHIDDeviceOpen.restype = c_int32
iokit.IOHIDDeviceOpen.argtypes = [c_void_p, c_uint32]
iokit.IOHIDDeviceClose.argtypes = [c_void_p, c_uint32]
iokit.IOHIDDeviceGetProperty.restype = c_void_p
iokit.IOHIDDeviceGetProperty.argtypes = [c_void_p, c_void_p]
iokit.IOHIDDeviceSetReport.restype = c_int32
iokit.IOHIDDeviceSetReport.argtypes = [c_void_p, c_int32, c_long, POINTER(c_uint8), c_long]
iokit.IOHIDDeviceGetReport.restype = c_int32
iokit.IOHIDDeviceGetReport.argtypes = [c_void_p, c_int32, c_long, POINTER(c_uint8), POINTER(c_long)]

kIOHIDReportTypeFeature = 2
UTF8 = 0x08000100

def _s(x): return cf.CFStringCreateWithCString(None, x.encode(), UTF8)
def _n(v):
    i = c_int32(v); return cf.CFNumberCreate(None, 9, byref(i))  # kCFNumberSInt32Type

def find(vid, pid, usage_page, usage):
    mgr = iokit.IOHIDManagerCreate(None, 0)
    d = cf.CFDictionaryCreateMutable(None, 0, byref(kCFTypeDictionaryKeyCallBacks), byref(kCFTypeDictionaryValueCallBacks))
    for k, v in (("VendorID", vid), ("ProductID", pid), ("DeviceUsagePage", usage_page), ("DeviceUsage", usage)):
        cf.CFDictionarySetValue(d, _s(k), _n(v))
    iokit.IOHIDManagerSetDeviceMatching(mgr, d)
    s = iokit.IOHIDManagerCopyDevices(mgr)
    if not s: return []
    n = cf.CFSetGetCount(s)
    arr = (c_void_p * n)()
    cf.CFSetGetValues(s, arr)
    return list(arr)

def open_dev(dev):
    return iokit.IOHIDDeviceOpen(dev, 0)  # kIOHIDOptionsTypeNone = shared

def set_feature(dev, data):
    buf = (c_uint8 * len(data)).from_buffer_copy(bytes(data))
    return iokit.IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, data[0], buf, len(data))

def get_feature(dev, report_id, size):
    buf = (c_uint8 * size)(); buf[0] = report_id
    ln = c_long(size)
    r = iokit.IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, report_id, buf, byref(ln))
    return r, bytes(buf[:ln.value])

def require(vid=0x258a, pid=0x010c, usage_page=0xff00, usage=0x01):
    """Return the first matching device, opened, or exit with a readable message."""
    import sys
    devs = find(vid, pid, usage_page, usage)
    if not devs:
        sys.exit("YUNZII YZ98 not found. Connect it with the USB-C cable (wired mode).")
    r = open_dev(devs[0])
    if r != 0:
        sys.exit(f"Couldn't open the keyboard (0x{r & 0xffffffff:08x}). Give your terminal Input Monitoring permission.")
    return devs[0]
