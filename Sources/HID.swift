import Foundation
import IOKit.hid

/// Wired protocol for Sinowealth 258A:010C keyboards (YUNZII / AULA / LEOBOG family).
/// Every transfer is a 520-byte feature report 0x06 on the vendor collection (usage page 0xFF00):
///   [0x06, cmd, sub, 0, total, index, size_lo, size_hi, payload...]
/// Reads send the header with cmd | 0x80, then fetch the payload with GetFeature.
enum YZ {
    static let vendorID = 0x258a
    static let productID = 0x010c
    static let reportID: UInt8 = 0x06
    static let reportLen = 520
    static let chunk = 512
    static let readFlag: UInt8 = 0x80

    static let ledBlockLen = 128
    static let keymapLen = 512
    static let perKeyLen = 384
    static let ledCount = 126

    enum Cmd: UInt8 {
        case model = 0x02
        case keymap = 0x03
        case led = 0x04
        case perKey = 0x06
        case live = 0x08
    }

    static let supportedModels: [UInt8: String] = [0xB3: "YUNZII YZ98"]
}

enum HIDError: LocalizedError {
    case io(String, IOReturn)
    case short(Int)
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .io(let op, let r): return "Keyboard \(op) failed (0x\(String(UInt32(bitPattern: r), radix: 16)))"
        case .short(let n): return "Keyboard sent a short reply (\(n) bytes)"
        case .invalid(let why): return why
        }
    }
}

final class YZDevice {
    let handle: IOHIDDevice

    init(_ handle: IOHIDDevice) { self.handle = handle }

    private func send(_ pk: [UInt8]) throws {
        var last: IOReturn = kIOReturnSuccess
        for _ in 0..<3 {
            last = pk.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(handle, kIOHIDReportTypeFeature, CFIndex(pk[0]), $0.baseAddress!, pk.count)
            }
            if last == kIOReturnSuccess { return }
            usleep(70_000)
        }
        throw HIDError.io("write", last)
    }

    private func packets(_ cmd: UInt8, _ sub: UInt8, _ len: Int, _ data: [UInt8]?) -> [[UInt8]] {
        let total = (len + YZ.chunk - 1) / YZ.chunk
        return (0..<total).map { i in
            let off = i * YZ.chunk
            let size = min(YZ.chunk, len - off)
            var p = [UInt8](repeating: 0, count: YZ.reportLen)
            p[0] = YZ.reportID
            p[1] = cmd
            p[2] = sub
            p[4] = UInt8(total)
            p[5] = UInt8(i)
            p[6] = UInt8(size & 0xff)
            p[7] = UInt8(size >> 8)
            if let d = data { p.replaceSubrange(8..<(8 + size), with: d[off..<(off + size)]) }
            return p
        }
    }

    func read(_ cmd: YZ.Cmd, sub: UInt8 = 0, len: Int) throws -> [UInt8] {
        var out: [UInt8] = []
        for pk in packets(cmd.rawValue | YZ.readFlag, sub, len, nil) {
            let size = Int(pk[6]) | Int(pk[7]) << 8
            usleep(20_000)
            try send(pk)
            usleep(20_000)
            var buf = [UInt8](repeating: 0, count: YZ.reportLen)
            buf[0] = YZ.reportID
            var n = CFIndex(YZ.reportLen)
            let r = IOHIDDeviceGetReport(handle, kIOHIDReportTypeFeature, CFIndex(YZ.reportID), &buf, &n)
            guard r == kIOReturnSuccess else { throw HIDError.io("read", r) }
            guard n >= 8 + size else { throw HIDError.short(n) }
            out += buf[8..<(8 + size)]
        }
        return out
    }

    func write(_ cmd: YZ.Cmd, sub: UInt8 = 0, data: [UInt8]) throws {
        for pk in packets(cmd.rawValue, sub, data.count, data) {
            usleep(20_000)
            try send(pk)
        }
    }

    /// Live frame: interleaved RGB for every LED. Not stored; the keyboard returns to its saved lighting when frames stop.
    func liveFrame(_ colours: [RGB]) throws {
        var data = [UInt8](repeating: 0, count: YZ.ledCount * 3)
        for (i, c) in colours.prefix(YZ.ledCount).enumerated() {
            data[i * 3] = c.r
            data[i * 3 + 1] = c.g
            data[i * 3 + 2] = c.b
        }
        for pk in packets(YZ.Cmd.live.rawValue, 0, data.count, data) { try send(pk) }
    }

    func modelID() throws -> UInt8 {
        let r = try read(.model, sub: 1, len: 6)
        return r[5]
    }

    func ledBlock() throws -> [UInt8] {
        let b = try read(.led, len: YZ.ledBlockLen)
        guard LED.valid(b) else { throw HIDError.invalid("Lighting settings failed their validity check; nothing was changed.") }
        return b
    }
}

/// The 128-byte lighting settings block (cmd 0x04).
enum LED {
    /// Set by the hardware Mac/Win switch: 1 = Mac, 0 = Win. In Mac mode the keyboard ignores the key table.
    static let switchOffset = 0

    static func valid(_ b: [UInt8]) -> Bool { b.count == YZ.ledBlockLen && b[126] == 0x5a && b[127] == 0xa5 }

    struct Effect: Identifiable, Hashable {
        let id: UInt8
        let name: String
        let speed: Bool
        let colour: Bool
    }

    /// Order matters: an effect's position is its settings slot (0x3a + 2 * slot).
    static let effects: [Effect] = [
        Effect(id: 1, name: "Static", speed: false, colour: true),
        Effect(id: 2, name: "Breathing", speed: true, colour: true),
        Effect(id: 3, name: "Rainbow", speed: true, colour: false),
        Effect(id: 4, name: "Flash Away", speed: true, colour: true),
        Effect(id: 5, name: "Raindrops", speed: true, colour: true),
        Effect(id: 6, name: "Rainbow Wheel", speed: true, colour: true),
        Effect(id: 7, name: "Ripples", speed: true, colour: true),
        Effect(id: 8, name: "Stars Twinkle", speed: true, colour: true),
        Effect(id: 9, name: "Shadow Fade", speed: true, colour: true),
        Effect(id: 10, name: "Retro Snake", speed: true, colour: true),
        Effect(id: 11, name: "Neon Stream", speed: true, colour: true),
        Effect(id: 12, name: "Reaction", speed: true, colour: true),
        Effect(id: 13, name: "Sine Wave", speed: true, colour: true),
        Effect(id: 14, name: "Scanner", speed: true, colour: true),
        Effect(id: 15, name: "Windmill", speed: true, colour: false),
        Effect(id: 16, name: "Waterfall", speed: true, colour: false),
        Effect(id: 17, name: "Blossoming", speed: true, colour: false),
        Effect(id: 18, name: "Storm", speed: true, colour: true),
        Effect(id: 21, name: "Per-key", speed: false, colour: false),
        Effect(id: 0, name: "Off", speed: false, colour: false),
    ]
    static let perKeyID: UInt8 = 21

    static let palette: [(name: String, rgb: (Double, Double, Double))] = [
        ("Red", (1, 0, 0)), ("Green", (0, 1, 0)), ("Blue", (0, 0, 1)), ("Yellow", (1, 1, 0)),
        ("Magenta", (1, 0, 1)), ("Cyan", (0, 1, 1)), ("White", (1, 1, 1)),
    ]
    static let randomColour: UInt8 = 7
    static let maxBrightness = 4
    static let maxSpeed = 4

    static func slot(of id: UInt8) -> Int? { effects.firstIndex { $0.id == id } }

    struct State: Equatable {
        var effect: UInt8
        var brightness: Int
        var speed: Int
        var colour: UInt8
    }

    static func state(_ b: [UInt8]) -> State {
        let id = b[10]
        guard let s = slot(of: id) else { return State(effect: id, brightness: 0, speed: 0, colour: 0) }
        let o = 0x3a + s * 2
        return State(effect: id, brightness: Int(b[o]), speed: Int(b[o + 1] >> 4), colour: b[o + 1] & 0x0f)
    }

    static func edit(_ b: inout [UInt8], _ s: State) {
        b[9] = s.effect == perKeyID ? 1 : 0
        b[10] = s.effect
        if let slot = slot(of: s.effect) {
            let o = 0x3a + slot * 2
            b[o] = UInt8(min(max(s.brightness, 0), maxBrightness))
            b[o + 1] = UInt8(min(max(s.speed, 0), maxSpeed)) << 4 | (s.colour & 0x0f)
        }
    }
}
