import Foundation

/// One physical key. Its key-table slot and LED index are both col * 6 + row.
struct KeyCap: Identifiable, Hashable {
    let row: Int
    let col: Int
    let label: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    var id: Int { col * 6 + row }
}

enum YZ98Layout {
    static let width = 19.5
    static let height = 6.25
    static let fnIndex = 9 * 6 + 5

    static let keys: [KeyCap] = {
        var k: [KeyCap] = []
        func add(_ r: Int, _ c: Int, _ l: String, _ x: Double, _ y: Double, w: Double = 1, h: Double = 1) {
            k.append(KeyCap(row: r, col: c, label: l, x: x, y: y, w: w, h: h))
        }
        func run(_ r: Int, from c: Int, _ labels: [String], x: Double, y: Double) {
            for (i, l) in labels.enumerated() { add(r, c + i, l, x + Double(i), y) }
        }

        add(0, 0, "Esc", 0, 0)
        run(0, from: 1, ["F1", "F2", "F3", "F4"], x: 1.25, y: 0)
        run(0, from: 5, ["F5", "F6", "F7", "F8"], x: 5.5, y: 0)
        run(0, from: 9, ["F9", "F10", "F11", "F12"], x: 9.75, y: 0)
        add(0, 13, "Del", 14, 0)
        run(0, from: 15, ["Home", "End", "PgUp", "PgDn"], x: 15.5, y: 0)

        let y1 = 1.25
        run(1, from: 0, ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="], x: 0, y: y1)
        add(1, 13, "Backspace", 13, y1, w: 2)
        run(1, from: 15, ["Num", "/", "*", "-"], x: 15.5, y: y1)

        let y2 = 2.25
        add(2, 0, "Tab", 0, y2, w: 1.5)
        run(2, from: 1, ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]"], x: 1.5, y: y2)
        add(2, 13, "\\", 13.5, y2, w: 1.5)
        run(2, from: 15, ["7", "8", "9"], x: 15.5, y: y2)
        add(2, 18, "+", 18.5, y2, h: 2)

        let y3 = 3.25
        add(3, 0, "Caps", 0, y3, w: 1.75)
        run(3, from: 1, ["A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'"], x: 1.75, y: y3)
        add(3, 13, "Enter", 12.75, y3, w: 2.25)
        run(3, from: 15, ["4", "5", "6"], x: 15.5, y: y3)

        let y4 = 4.25
        add(4, 0, "Shift", 0, y4, w: 2.25)
        run(4, from: 1, ["Z", "X", "C", "V", "B", "N", "M", ",", ".", "/"], x: 2.25, y: y4)
        add(4, 13, "Shift", 12.25, y4, w: 1.75)
        add(4, 14, "↑", 14.5, y4)
        run(4, from: 15, ["1", "2", "3"], x: 15.5, y: y4)
        add(4, 18, "Enter", 18.5, y4, h: 2)

        let y5 = 5.25
        add(5, 0, "Ctrl", 0, y5, w: 1.25)
        add(5, 1, "Win", 1.25, y5, w: 1.25)
        add(5, 2, "Alt", 2.5, y5, w: 1.25)
        add(5, 5, "Space", 3.75, y5, w: 6.25)
        add(5, 8, "Alt", 10, y5)
        add(5, 9, "Fn", 11, y5)
        add(5, 10, "Ctrl", 12, y5)
        add(5, 13, "←", 13.5, y5)
        add(5, 14, "↓", 14.5, y5)
        add(5, 15, "→", 15.5, y5)
        add(5, 16, "0", 16.5, y5)
        add(5, 17, ".", 17.5, y5)
        return k
    }()

    static func key(_ row: Int, _ col: Int) -> KeyCap? { keys.first { $0.row == row && $0.col == col } }
}

/// Key-table entries are 4 bytes: [type, modifiers, hi, lo].
/// type 0x00 = keyboard (modifier bits + HID usage), 0x02 = media (consumer usage), 0x0d = Fn.
enum Keycodes {
    typealias Code = [UInt8]

    static let none: Code = [0, 0, 0, 0]

    static let usage: [UInt8: String] = {
        var m: [UInt8: String] = [:]
        for i in 0..<26 { m[UInt8(0x04 + i)] = String(UnicodeScalar(UInt8(65 + i))) }
        for i in 0..<9 { m[UInt8(0x1e + i)] = "\(i + 1)" }
        m[0x27] = "0"
        m[0x28] = "Enter"; m[0x29] = "Esc"; m[0x2a] = "Backspace"; m[0x2b] = "Tab"; m[0x2c] = "Space"
        m[0x2d] = "-"; m[0x2e] = "="; m[0x2f] = "["; m[0x30] = "]"; m[0x31] = "\\"; m[0x33] = ";"
        m[0x34] = "'"; m[0x35] = "`"; m[0x36] = ","; m[0x37] = "."; m[0x38] = "/"; m[0x39] = "Caps Lock"
        for i in 0..<12 { m[UInt8(0x3a + i)] = "F\(i + 1)" }
        m[0x46] = "Print Screen"; m[0x47] = "Scroll Lock"; m[0x48] = "Pause"; m[0x49] = "Insert"
        m[0x4a] = "Home"; m[0x4b] = "Page Up"; m[0x4c] = "Delete"; m[0x4d] = "End"; m[0x4e] = "Page Down"
        m[0x4f] = "→"; m[0x50] = "←"; m[0x51] = "↓"; m[0x52] = "↑"
        m[0x53] = "Num Lock"; m[0x54] = "Num /"; m[0x55] = "Num *"; m[0x56] = "Num -"; m[0x57] = "Num +"
        m[0x58] = "Num Enter"
        for i in 0..<9 { m[UInt8(0x59 + i)] = "Num \(i + 1)" }
        m[0x62] = "Num 0"; m[0x63] = "Num ."; m[0x65] = "Menu"
        for i in 0..<12 { m[UInt8(0x68 + i)] = "F\(13 + i)" }
        return m
    }()

    static let modifiers: [(bit: UInt8, name: String, short: String)] = [
        (0x01, "Left Control", "⌃"), (0x02, "Left Shift", "⇧"), (0x04, "Left Option (Alt)", "⌥"),
        (0x08, "Left Command (Win)", "⌘"), (0x10, "Right Control", "R⌃"), (0x20, "Right Shift", "R⇧"),
        (0x40, "Right Option (Alt)", "R⌥"), (0x80, "Right Command (Win)", "R⌘"),
    ]

    static let media: [(usage: UInt16, name: String)] = [
        (0xcd, "Play / Pause"), (0xb5, "Next Track"), (0xb6, "Previous Track"), (0xb7, "Stop"),
        (0xe2, "Mute"), (0xe9, "Volume Up"), (0xea, "Volume Down"),
        (0x6f, "Screen Brightness Up"), (0x70, "Screen Brightness Down"),
    ]

    static func key(_ usage: UInt8) -> Code { [0, 0, 0, usage] }
    static func modifier(_ bit: UInt8) -> Code { [0, bit, 0, 0] }

    static func label(_ c: Code) -> String {
        guard c.count == 4 else { return "?" }
        switch c[0] {
        case 0x00:
            if c[1] == 0 && c[3] == 0 { return "None" }
            if c[3] == 0, let m = modifiers.first(where: { $0.bit == c[1] }) { return m.short + " " + shortName(m.name) }
            var parts = modifiers.filter { c[1] & $0.bit != 0 }.map(\.short)
            parts.append(usage[c[3]] ?? String(format: "0x%02X", c[3]))
            return parts.joined(separator: parts.count > 1 ? "+" : "")
        case 0x02:
            let u = UInt16(c[2]) << 8 | UInt16(c[3])
            return media.first { $0.usage == u }?.name ?? String(format: "Media 0x%03X", u)
        case 0x0d: return "Fn"
        case 0x03: return "Macro"
        case 0x07: return "Lighting fn"
        case 0x08: return "System fn"
        default: return c.map { String(format: "%02x", $0) }.joined()
        }
    }

    private static func shortName(_ n: String) -> String {
        n.replacingOccurrences(of: "Left ", with: "").replacingOccurrences(of: "Right ", with: "")
            .replacingOccurrences(of: " (Alt)", with: "").replacingOccurrences(of: " (Win)", with: "")
    }

    struct Target: Identifiable, Hashable {
        let code: Code
        let name: String
        var id: String { code.map { String(format: "%02x", $0) }.joined() }
    }

    static let groups: [(name: String, targets: [Target])] = {
        func keys(_ range: [UInt8]) -> [Target] { range.compactMap { u in usage[u].map { Target(code: key(u), name: $0) } } }
        return [
            ("Modifiers", modifiers.map { Target(code: modifier($0.bit), name: $0.name) }),
            ("Letters", keys(Array(0x04...0x1d))),
            ("Numbers", keys(Array(0x1e...0x27))),
            ("Editing & symbols", keys([0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x39, 0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38])),
            ("Navigation", keys([0x49, 0x4c, 0x4a, 0x4d, 0x4b, 0x4e, 0x4f, 0x50, 0x51, 0x52])),
            ("Function keys", keys(Array(0x3a...0x45) + Array(0x68...0x73))),
            ("Numpad", keys(Array(0x53...0x63))),
            ("System", keys([0x46, 0x47, 0x48, 0x65])),
            ("Media", media.map { Target(code: [0x02, 0, UInt8($0.usage >> 8), UInt8($0.usage & 0xff)], name: $0.name) }),
            ("Other", [Target(code: none, name: "None (disable key)")]),
        ]
    }()
}

/// Win-mode key table setup that reproduces the YZ98's Mac mode, with a choice of what the top row sends.
/// Mac mode itself ignores the key table, so these only take effect with the switch on Win.
enum TopRow {
    /// F1–F12 sit at row 0, columns 1–12.
    static func index(_ i: Int) -> Int { (i + 1) * 6 }

    static let fKeys: [Keycodes.Code] = (0..<12).map { [0, 0, 0, UInt8(0x3a + $0)] }

    /// Mac media functions for the top row: what the keyboard's own Mac mode sends (recorded from a YZ98),
    /// with key combos replaced by single media codes where macOS needs them.
    static let macMedia: [Keycodes.Code] = [
        [0x02, 0, 0, 0x70], [0x02, 0, 0, 0x6f],   // screen brightness down / up
        [0x02, 0, 0x02, 0x9f],                    // Mission Control (Mac mode sends Ctrl+Up, which arrives out of order)
        [0x02, 0, 0, 0xcf],                       // dictation
        [0x02, 0, 0x02, 0xa2],                    // Apps / Launchpad (Mac mode's Ctrl+Down never worked)
        [0, 0x08, 0, 0x2c],                       // Cmd+Space: Spotlight (works despite the ordering quirk)
        [0x02, 0, 0, 0xb6], [0x02, 0, 0, 0xb5], [0x02, 0, 0, 0xcd],   // previous, next, play/pause
        [0x02, 0, 0, 0xe2], [0x02, 0, 0, 0xea], [0x02, 0, 0, 0xe9],   // mute, volume down, volume up
    ]
    static let macMediaNames = ["Brightness −", "Brightness +", "Mission Control", "Dictation", "Apps", "Spotlight",
                                "Previous", "Next", "Play/Pause", "Mute", "Volume −", "Volume +"]

    /// Mac mode's modifiers: Win key → Option, Alt → Command, right Alt → right Command.
    static let macModifiers: [Int: Keycodes.Code] = [
        1 * 6 + 5: [0, 0x04, 0, 0],
        2 * 6 + 5: [0, 0x08, 0, 0],
        8 * 6 + 5: [0, 0x80, 0, 0],
    ]
}
