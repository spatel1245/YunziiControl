import AppKit
import Foundation
import IOKit.hid

struct RGB: Equatable, Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    static let off = RGB(r: 0, g: 0, b: 0)
}

/// Snapshot of everything the app can write, taken the first time a keyboard is seen.
struct Snapshot: Codable {
    var model: UInt8
    var date: Date
    var led: [UInt8]
    var keymaps: [[UInt8]]
    var perKey: [[UInt8]]
}

final class KeyboardModel: ObservableObject {
    enum Status: Equatable {
        case needsPermission
        case disconnected
        case loading
        case ready
        case unsupported(UInt8)
        case failed(String)
    }

    static let layers = 4
    static let perKeyGroups = 2

    @Published var status: Status = .disconnected
    @Published var modelName = ""
    @Published var led: [UInt8] = []
    @Published var keymaps: [[UInt8]] = []
    @Published var perKey: [UInt8] = []
    @Published var original: Snapshot?
    @Published var busy = false
    @Published var message: String?

    private var manager: IOHIDManager?
    private var device: YZDevice?
    private var poll: Timer?
    private var frameInFlight = false
    private let io = DispatchQueue(label: "yunzii.io")

    // MARK: Connection

    func start() {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey: YZ.vendorID,
            kIOHIDProductIDKey: YZ.productID,
            kIOHIDDeviceUsagePageKey: 0xff00,
            kIOHIDDeviceUsageKey: 0x01,
        ]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, dev in
            Unmanaged<KeyboardModel>.fromOpaque(ctx!).takeUnretainedValue().attached(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, dev in
            Unmanaged<KeyboardModel>.fromOpaque(ctx!).takeUnretainedValue().removed(dev)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        manager = mgr
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshLED() }
    }

    /// The Mac/Win switch is only visible in the LED block, so re-read it while idle.
    private func refreshLED() {
        guard let dev = device, status == .ready, !busy else { return }
        io.async {
            guard let b = try? dev.ledBlock() else { return }
            DispatchQueue.main.async { if !self.busy, b != self.led { self.led = b } }
        }
    }

    private func attached(_ dev: IOHIDDevice) {
        let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        if r == kIOReturnNotPermitted {
            status = .needsPermission
            return
        }
        guard r == kIOReturnSuccess else {
            status = .failed("Couldn't open the keyboard (0x\(String(UInt32(bitPattern: r), radix: 16))).")
            return
        }
        device = YZDevice(dev)
        reload()
    }

    private func removed(_ dev: IOHIDDevice) {
        guard let d = device, CFEqual(d.handle, dev) else { return }
        device = nil
        status = .disconnected
    }

    func reload(quiet: Bool = false) {
        guard let dev = device else { return }
        if !quiet { status = .loading }
        io.async {
            do {
                let model = try dev.modelID()
                let led = try dev.ledBlock()
                let keymaps = try (0..<Self.layers).map { try dev.read(.keymap, sub: UInt8($0), len: YZ.keymapLen) }
                let perKey = try (0..<Self.perKeyGroups).map { try dev.read(.perKey, sub: UInt8($0), len: YZ.perKeyLen) }
                DispatchQueue.main.async {
                    self.led = led
                    self.keymaps = keymaps
                    self.perKey = perKey[0]
                    self.original = self.loadOrSaveSnapshot(Snapshot(model: model, date: Date(), led: led, keymaps: keymaps, perKey: perKey))
                    if let name = YZ.supportedModels[model] {
                        self.modelName = name
                        self.status = .ready
                    } else {
                        self.modelName = String(format: "Unknown model 0x%02X", model)
                        self.status = .unsupported(model)
                    }
                }
            } catch {
                DispatchQueue.main.async { self.status = .failed(error.localizedDescription) }
            }
        }
    }

    // MARK: Snapshot of the original settings

    private static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("YunziiControl", isDirectory: true)
    }

    private func snapshotURL(_ model: UInt8) -> URL {
        Self.supportDir.appendingPathComponent(String(format: "original-%02x.json", model))
    }

    private func loadOrSaveSnapshot(_ current: Snapshot) -> Snapshot {
        let url = snapshotURL(current.model)
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return s
        }
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(current) { try? data.write(to: url) }
        return current
    }

    // MARK: Writes

    /// Runs a write on the I/O queue, then re-reads everything so the UI shows what the keyboard actually stored.
    private func perform(_ done: String, _ work: @escaping (YZDevice) throws -> Void) {
        guard let dev = device, status == .ready, !busy else { return }
        busy = true
        message = nil
        io.async {
            var failure: String?
            do { try work(dev) } catch { failure = error.localizedDescription }
            DispatchQueue.main.async {
                self.busy = false
                self.message = failure ?? done
                self.reload(quiet: true)
            }
        }
    }

    private static func editBlock(_ dev: YZDevice, _ change: (inout [UInt8]) -> Void) throws {
        var b = try dev.ledBlock()
        change(&b)
        try dev.write(.led, data: b)
        usleep(100_000)
        guard try dev.ledBlock() == b else { throw HIDError.invalid("The keyboard didn't keep the new lighting settings.") }
    }

    func setEffect(_ s: LED.State) {
        perform("Lighting saved to the keyboard.") { dev in
            try Self.editBlock(dev) { LED.edit(&$0, s) }
        }
    }

    func savePerKey(_ colours: [RGB], brightness: Int) {
        var payload = perKey
        for (i, c) in colours.enumerated() where i < YZ.ledCount {
            payload[i] = c.r
            payload[YZ.ledCount + i] = c.g
            payload[2 * YZ.ledCount + i] = c.b
        }
        perform("Per-key colours saved to the keyboard.") { dev in
            try dev.write(.perKey, sub: 0, data: payload)
            usleep(50_000)
            guard try dev.read(.perKey, sub: 0, len: YZ.perKeyLen) == payload else {
                throw HIDError.invalid("The keyboard didn't keep the per-key colours.")
            }
            try Self.editBlock(dev) {
                var s = LED.state($0)
                s.effect = LED.perKeyID
                s.brightness = brightness
                LED.edit(&$0, s)
            }
        }
    }

    func writeKeymap(layer: Int, changes: [Int: Keycodes.Code]) {
        perform("Key mapping saved to the keyboard.") { dev in try Self.writeLayer(dev, layer, changes) }
    }

    /// Read a key layer, apply changes (never the Fn key), write it back and verify.
    private static func writeLayer(_ dev: YZDevice, _ layer: Int, _ changes: [Int: Keycodes.Code]) throws {
        var table = try dev.read(.keymap, sub: UInt8(layer), len: YZ.keymapLen)
        let fn = YZ98Layout.fnIndex * 4
        let fnBefore = Array(table[fn..<(fn + 4)])
        for (idx, code) in changes where idx != YZ98Layout.fnIndex {
            table.replaceSubrange((idx * 4)..<(idx * 4 + 4), with: code)
        }
        guard Array(table[fn..<(fn + 4)]) == fnBefore else { throw HIDError.invalid("Refusing to change the Fn key.") }
        try dev.write(.keymap, sub: UInt8(layer), data: table)
        usleep(50_000)
        guard try dev.read(.keymap, sub: UInt8(layer), len: YZ.keymapLen) == table else {
            throw HIDError.invalid("The keyboard didn't keep the new key mapping.")
        }
    }

    /// Win-mode setup: Mac modifiers plus the chosen top row; the Fn layer gets the other set.
    func setTopRow(fKeysFirst: Bool) {
        var base = TopRow.macModifiers
        var fnLayer: [Int: Keycodes.Code] = [:]
        for i in 0..<12 {
            base[TopRow.index(i)] = fKeysFirst ? TopRow.fKeys[i] : TopRow.macMedia[i]
            fnLayer[TopRow.index(i)] = fKeysFirst ? TopRow.macMedia[i] : TopRow.fKeys[i]
        }
        perform(fKeysFirst ? "Top row now sends F1–F12 (Fn for media)." : "Top row now sends media keys (Fn for F1–F12).") { dev in
            try Self.writeLayer(dev, 0, base)
            try Self.writeLayer(dev, 1, fnLayer)
        }
    }

    /// Put back the base and Fn layers from the first-launch snapshot.
    func restoreKeyTable() {
        guard let s = original, s.keymaps.count >= 2 else { return }
        perform("Original key table restored.") { dev in
            for layer in 0..<2 {
                try dev.write(.keymap, sub: UInt8(layer), data: s.keymaps[layer])
                usleep(50_000)
                guard try dev.read(.keymap, sub: UInt8(layer), len: YZ.keymapLen) == s.keymaps[layer] else {
                    throw HIDError.invalid("The keyboard didn't keep the restored key table.")
                }
            }
        }
    }

    /// nil when the key table isn't in either of our layouts (e.g. never set up).
    var topRowFKeysFirst: Bool? {
        guard keymaps.count >= 2 else { return nil }
        let base = (0..<12).map { code(layer: 0, index: TopRow.index($0)) }
        let modsOK = TopRow.macModifiers.allSatisfy { code(layer: 0, index: $0.key) == $0.value }
        guard modsOK else { return nil }
        if base == TopRow.fKeys { return true }
        if base == TopRow.macMedia { return false }
        return nil
    }

    func restoreOriginal() {
        guard let s = original else { return }
        perform("Original settings restored.") { dev in
            for (i, p) in s.perKey.enumerated() { try dev.write(.perKey, sub: UInt8(i), data: p) }
            var led = s.led
            led[LED.switchOffset] = try dev.ledBlock()[LED.switchOffset]
            try dev.write(.led, data: led)
        }
    }

    // MARK: Live frames

    /// Sends one live frame unless a settings write or another frame is in progress.
    func sendLiveFrame(_ colours: [RGB]) {
        guard let dev = device, status == .ready, !busy, !frameInFlight else { return }
        frameInFlight = true
        io.async {
            try? dev.liveFrame(colours)
            DispatchQueue.main.async { self.frameInFlight = false }
        }
    }

    /// What the rest of the board should show during live lighting: the saved Static or Per-key colours.
    /// Animated effects can't be reproduced, so they fall back to their colour (or white).
    func liveBase() -> [RGB] {
        let s = lighting
        let scale = Double(min(max(s.brightness, 0), LED.maxBrightness)) / Double(LED.maxBrightness)
        func dim(_ c: RGB) -> RGB { RGB(r: UInt8(Double(c.r) * scale), g: UInt8(Double(c.g) * scale), b: UInt8(Double(c.b) * scale)) }
        if s.effect == 0 { return Array(repeating: .off, count: YZ.ledCount) }
        if s.effect == LED.perKeyID { return perKeyColours.map(dim) }
        let white = RGB(r: 255, g: 255, b: 255)
        let base: RGB
        if Int(s.colour) < LED.palette.count {
            let p = LED.palette[Int(s.colour)].rgb
            base = RGB(r: UInt8(p.0 * 255), g: UInt8(p.1 * 255), b: UInt8(p.2 * 255))
        } else {
            base = white
        }
        return Array(repeating: dim(base), count: YZ.ledCount)
    }

    // MARK: Helpers for views

    /// Position of the keyboard's Mac/Win switch.
    var macMode: Bool { led.count == YZ.ledBlockLen && led[LED.switchOffset] == 1 }

    var lighting: LED.State { led.count == YZ.ledBlockLen ? LED.state(led) : LED.State(effect: 0, brightness: 0, speed: 0, colour: 0) }

    func code(layer: Int, index: Int) -> Keycodes.Code {
        guard layer < keymaps.count else { return Keycodes.none }
        return Array(keymaps[layer][(index * 4)..<(index * 4 + 4)])
    }

    func originalCode(layer: Int, index: Int) -> Keycodes.Code? {
        guard let s = original, layer < s.keymaps.count else { return nil }
        return Array(s.keymaps[layer][(index * 4)..<(index * 4 + 4)])
    }

    var perKeyColours: [RGB] {
        guard perKey.count == YZ.perKeyLen else { return Array(repeating: .off, count: YZ.ledCount) }
        return (0..<YZ.ledCount).map { RGB(r: perKey[$0], g: perKey[YZ.ledCount + $0], b: perKey[2 * YZ.ledCount + $0]) }
    }

    var perKeyBrightness: Int {
        guard led.count == YZ.ledBlockLen, let slot = LED.slot(of: LED.perKeyID) else { return LED.maxBrightness }
        return Int(led[0x3a + slot * 2])
    }
}
