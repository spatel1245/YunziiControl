import AppKit
import SwiftUI

extension RGB {
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    var isLight: Bool { 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b) > 140 }

    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(r: UInt8((c.redComponent * 255).rounded()), g: UInt8((c.greenComponent * 255).rounded()), b: UInt8((c.blueComponent * 255).rounded()))
    }
}

// MARK: - Root

struct ContentView: View {
    @ObservedObject var kb: KeyboardModel
    @ObservedObject var live: LiveEngine

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch kb.status {
                case .ready:
                    TabView {
                        LightingView(kb: kb).tabItem { Text("Lighting") }
                        PerKeyView(kb: kb).tabItem { Text("Per-key colours") }
                        TopRowView(kb: kb).tabItem { Text("Top row") }
                        LiveView(kb: kb, live: live).tabItem { Text("Live") }
                    }
                    .padding()
                case .loading:
                    centered { ProgressView("Reading keyboard settings…") }
                case .disconnected:
                    centered {
                        notice("keyboard", "Plug in your YUNZII YZ98",
                               "Connect it with a USB-C cable. Settings can only be changed over the cable, not 2.4 GHz or Bluetooth.")
                    }
                case .needsPermission:
                    PermissionView()
                case .unsupported(let id):
                    centered {
                        notice("exclamationmark.triangle", "This keyboard isn't supported yet",
                               String(format: "It reports model ID 0x%02X. This app only knows the YZ98 (0xB3), so it won't write anything to avoid sending the wrong settings.", id))
                    }
                case .failed(let why):
                    centered {
                        VStack(spacing: 12) {
                            notice("xmark.octagon", "Couldn't talk to the keyboard", why)
                            Button("Try again") { kb.reload() }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 640)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(kb.status == .ready ? Color.green : Color.secondary.opacity(0.5)).frame(width: 9, height: 9)
            Text(kb.status == .ready ? kb.modelName : "No keyboard").font(.headline)
            if kb.busy { ProgressView().controlSize(.small) }
            if kb.status == .ready {
                Text(kb.macMode ? "Switch: Mac" : "Switch: Win")
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
            }
            if let m = kb.message { Text(m).foregroundColor(.secondary).lineLimit(1) }
            Spacer()
            if kb.status == .ready, kb.original != nil {
                Button("Restore first-launch settings…") { confirmRestore() }
                    .disabled(kb.busy)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func confirmRestore() {
        let a = NSAlert()
        a.messageText = "Restore the settings this keyboard had when the app first saw it?"
        if let d = kb.original?.date { a.informativeText = "Snapshot taken \(d.formatted(date: .abbreviated, time: .shortened)). This rewrites the lighting and per-key colours." }
        a.addButton(withTitle: "Restore")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { kb.restoreOriginal() }
    }

    private func centered<V: View>(@ViewBuilder _ v: () -> V) -> some View {
        VStack { Spacer(); v(); Spacer() }.frame(maxWidth: .infinity)
    }
}

func notice(_ icon: String, _ title: String, _ body: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: icon).font(.system(size: 40)).foregroundColor(.secondary)
        Text(title).font(.title2.bold())
        Text(body).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
    }
}

struct PermissionView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            notice("lock.shield", "Allow Input Monitoring",
                   "macOS only lets apps change a keyboard's settings with this permission. Turn on YunziiControl in Privacy & Security → Input Monitoring, then reopen the app.")
            HStack {
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                }
                Button("Reopen app") { relaunch() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func relaunch() {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

// MARK: - Keyboard drawing

struct KeyStyle {
    var fill: Color
    var text: Color
    var label: String
    var highlight: Color?
}

struct KeyView: View {
    let style: KeyStyle
    let unit: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.12)
        let stroke: Color = style.highlight ?? Color.black.opacity(0.35)
        let width: CGFloat = style.highlight == nil ? 1 : 3
        return shape.fill(style.fill)
            .overlay(shape.stroke(stroke, lineWidth: width))
            .overlay(label)
    }

    private var label: some View {
        Text(style.label)
            .font(.system(size: max(8, unit * 0.2), weight: .medium))
            .foregroundColor(style.text)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .padding(2)
    }
}

struct KeyboardCanvas: View {
    let style: (KeyCap) -> KeyStyle
    let onHit: (KeyCap, Bool) -> Void
    @StateObject private var hit = HitTracker()

    var body: some View {
        GeometryReader { geo in
            let u = min(geo.size.width / YZ98Layout.width, geo.size.height / YZ98Layout.height)
            let gap = u * 0.06
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: u * 0.25)
                    .fill(Color(white: 0.16))
                    .frame(width: YZ98Layout.width * u + gap * 4, height: YZ98Layout.height * u + gap * 4)
                    .offset(x: -gap * 2, y: -gap * 2)
                ForEach(YZ98Layout.keys) { k in
                    KeyView(style: style(k), unit: u)
                        .frame(width: k.w * u - gap * 2, height: k.h * u - gap * 2)
                        .offset(x: k.x * u + gap, y: k.y * u + gap)
                }
            }
            .frame(width: YZ98Layout.width * u, height: YZ98Layout.height * u, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let p = CGPoint(x: v.location.x / u, y: v.location.y / u)
                        let start = v.translation == .zero
                        guard let k = YZ98Layout.keys.first(where: { p.x >= $0.x && p.x < $0.x + $0.w && p.y >= $0.y && p.y < $0.y + $0.h }) else { return }
                        if start || k.id != hit.last {
                            hit.last = k.id
                            onHit(k, start)
                        }
                    }
                    .onEnded { _ in hit.last = nil }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(YZ98Layout.width / YZ98Layout.height, contentMode: .fit)
        .padding(10)
    }
}

// MARK: - Lighting

struct LightingView: View {
    @ObservedObject var kb: KeyboardModel
    @StateObject private var st = LightingState()

    private var current: LED.State { kb.lighting }
    private var effect: LED.Effect? { LED.effects.first { $0.id == current.effect } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Effect").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(LED.effects) { e in
                    Button {
                        var s = current
                        s.effect = e.id
                        if let slot = LED.slot(of: e.id), kb.led.count == YZ.ledBlockLen {
                            let o = 0x3a + slot * 2
                            s.brightness = Int(kb.led[o])
                            s.speed = Int(kb.led[o + 1] >> 4)
                            s.colour = kb.led[o + 1] & 0x0f
                        }
                        kb.setEffect(s)
                    } label: {
                        Text(e.name).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(e.id == current.effect ? .accentColor : nil)
                    .disabled(kb.busy)
                }
            }

            Text("Colour").font(.headline)
            HStack(spacing: 10) {
                ForEach(Array(LED.palette.enumerated()), id: \.offset) { i, p in
                    swatch(Color(red: p.rgb.0, green: p.rgb.1, blue: p.rgb.2), selected: current.colour == UInt8(i), help: p.name) {
                        var s = current
                        s.colour = UInt8(i)
                        kb.setEffect(s)
                    }
                }
                swatch(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center),
                       selected: current.colour == LED.randomColour, help: "Random / multicolour") {
                    var s = current
                    s.colour = LED.randomColour
                    kb.setEffect(s)
                }
            }
            .disabled(!(effect?.colour ?? false) || kb.busy)
            .opacity(effect?.colour ?? false ? 1 : 0.4)

            HStack(spacing: 40) {
                slider("Brightness", value: $st.brightness, max: LED.maxBrightness) {
                    var s = current
                    s.brightness = Int(st.brightness)
                    kb.setEffect(s)
                }
                slider("Speed", value: $st.speed, max: LED.maxSpeed) {
                    var s = current
                    s.speed = Int(st.speed)
                    kb.setEffect(s)
                }
                .disabled(!(effect?.speed ?? false))
                .opacity(effect?.speed ?? false ? 1 : 0.4)
            }
            .disabled(kb.busy)

            Text("Changes are saved on the keyboard and survive unplugging. Effect names come from the AULA driver this firmware shares, so a few may look different on the YZ98.")
                .font(.callout).foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .onAppear(perform: sync)
        .onChange(of: kb.led) { _ in sync() }
    }

    private func sync() {
        st.brightness = Double(current.brightness)
        st.speed = Double(current.speed)
    }

    private func swatch<S: ShapeStyle>(_ fill: S, selected: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(fill).frame(width: 30, height: 30)
                .overlay(Circle().stroke(selected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: selected ? 3 : 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func slider(_ title: String, value: Binding<Double>, max: Int, commit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading) {
            Text("\(title): \(Int(value.wrappedValue))").font(.headline)
            Slider(value: value, in: 0...Double(max), step: 1) { editing in if !editing { commit() } }
                .frame(width: 260)
        }
    }
}

// MARK: - Per-key colours

struct PerKeyView: View {
    @ObservedObject var kb: KeyboardModel
    @StateObject private var st = PerKeyState()

    private let presets: [Color] = [.white, .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KeyboardCanvas(style: { k in
                let c = k.id < st.colours.count ? st.colours[k.id] : .off
                return KeyStyle(fill: c == .off ? Color(white: 0.28) : c.color, text: c.isLight ? .black : .white, label: k.label, highlight: nil)
            }, onHit: { k, _ in
                guard k.id < st.colours.count else { return }
                st.colours[k.id] = RGB(st.brush)
                st.dirty = true
            })

            HStack(spacing: 10) {
                ColorPicker("Brush", selection: $st.brush, supportsOpacity: false).fixedSize()
                ForEach(presets, id: \.self) { c in
                    Button { st.brush = c } label: {
                        Circle().fill(c).frame(width: 22, height: 22).overlay(Circle().stroke(Color.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                }
                Button("Off") { st.brush = .black }
                Divider().frame(height: 22)
                Button("Fill all") { setAll(RGB(st.brush)) }
                Button("Clear all") { setAll(.off) }
                Button("Revert") { sync() }.disabled(!st.dirty)
                Spacer()
                Text("Brightness \(Int(st.brightness))")
                Slider(value: $st.brightness, in: 0...Double(LED.maxBrightness), step: 1).frame(width: 140)
                Button("Save to keyboard") {
                    kb.savePerKey(st.colours, brightness: Int(st.brightness))
                    st.dirty = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(kb.busy)
            }
            Text("Click or drag across keys to paint them. Saving stores the colours on the keyboard and switches it to per-key mode.")
                .font(.callout).foregroundColor(.secondary)
        }
        .padding()
        .onAppear(perform: sync)
    }

    private func setAll(_ c: RGB) {
        for k in YZ98Layout.keys where k.id < st.colours.count { st.colours[k.id] = c }
        st.dirty = true
    }

    private func sync() {
        st.colours = kb.perKeyColours
        st.brightness = Double(kb.perKeyBrightness)
        st.dirty = false
    }
}

// MARK: - Remapping

struct RemapView: View {
    @ObservedObject var kb: KeyboardModel
    @StateObject private var st = RemapState()

    private let layerNames = ["Base layer", "Fn layer", "Layer 3", "Layer 4"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("", selection: $st.layer) {
                    ForEach(0..<2, id: \.self) { Text(layerNames[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                .disabled(!st.staged.isEmpty)
                if st.layer == 0 {
                    Button("Mac modifier layout") { macLayout() }
                        .help("For Win-switch mode: Win key → ⌥ Option, Alt → ⌘ Command, right Alt → ⌘ Command (the same as Mac mode)")
                }
                Spacer()
                if !st.staged.isEmpty {
                    Text("\(st.staged.count) unsaved change\(st.staged.count == 1 ? "" : "s")").foregroundColor(.orange)
                    Button("Discard") { st.staged = [:] }
                }
                Button("Write to keyboard") {
                    kb.writeKeymap(layer: st.layer, changes: st.staged)
                    st.staged = [:]
                }
                .buttonStyle(.borderedProminent)
                .disabled(st.staged.isEmpty || kb.busy)
            }

            if kb.macMode {
                Label("The keyboard's switch is on Mac. In Mac mode it uses a built-in layout and ignores remaps, so changes here only take effect with the switch on Win. Tip: set the switch to Win and press \"Mac modifier layout\" to get the same ⌘/⌥ keys as Mac mode, plus your own remaps.", systemImage: "info.circle")
                    .font(.callout)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.18)))
            }

            KeyboardCanvas(style: style, onHit: { k, start in
                guard start else { return }
                st.selected = k.id == YZ98Layout.fnIndex ? nil : k
            })
            .frame(maxHeight: 330)

            if let k = st.selected {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Key: \(k.label)").font(.headline)
                        Text("Sends: \(Keycodes.label(effective(k.id)))")
                        if let o = kb.originalCode(layer: st.layer, index: k.id), o != effective(k.id) {
                            Button("Reset to \(Keycodes.label(o))") { stage(k.id, o) }
                        }
                        Button("Done") { st.selected = nil }
                    }
                    .frame(width: 220, alignment: .leading)
                    VStack(alignment: .leading) {
                        TextField("Search keys", text: $st.search).textFieldStyle(.roundedBorder)
                        List {
                            ForEach(filteredGroups, id: \.name) { g in
                                Section(g.name) {
                                    ForEach(g.targets) { t in
                                        Button(t.name) { stage(k.id, t.code) }
                                            .buttonStyle(.plain)
                                            .foregroundColor(t.code == effective(k.id) ? .accentColor : .primary)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: 180)
            } else {
                Text(st.layer == 0
                     ? "Click a key to choose what it sends. Fn can't be remapped, so you can always reach the Fn shortcuts."
                     : "The Fn layer is what each key does while Fn is held. Changing it replaces Yunzii's built-in Fn shortcut for that key.")
                    .font(.callout).foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
        .onChange(of: st.layer) { _ in st.selected = nil }
    }

    private var filteredGroups: [(name: String, targets: [Keycodes.Target])] {
        guard !st.search.isEmpty else { return Keycodes.groups }
        return Keycodes.groups.compactMap { g in
            let t = g.targets.filter { $0.name.localizedCaseInsensitiveContains(st.search) }
            return t.isEmpty ? nil : (g.name, t)
        }
    }

    private func effective(_ idx: Int) -> Keycodes.Code { st.staged[idx] ?? kb.code(layer: st.layer, index: idx) }

    private func stage(_ idx: Int, _ code: Keycodes.Code) {
        if code == kb.code(layer: st.layer, index: idx) { st.staged[idx] = nil } else { st.staged[idx] = code }
    }

    private func style(_ k: KeyCap) -> KeyStyle {
        let code = effective(k.id)
        let label = Keycodes.label(code)
        if k.id == YZ98Layout.fnIndex {
            return KeyStyle(fill: Color(white: 0.2), text: .gray, label: "Fn 🔒", highlight: nil)
        }
        let changedFromOriginal = kb.originalCode(layer: st.layer, index: k.id).map { $0 != code } ?? false
        let fill: Color = st.staged[k.id] != nil ? .orange.opacity(0.85)
            : changedFromOriginal ? .blue.opacity(0.55)
            : code == Keycodes.none ? Color(white: 0.24) : Color(white: 0.36)
        return KeyStyle(fill: fill, text: code == Keycodes.none ? .gray : .white,
                        label: code == Keycodes.none ? (st.layer == 0 ? "—" : "") : label,
                        highlight: st.selected?.id == k.id ? .accentColor : nil)
    }

    private func macLayout() {
        guard let lWin = YZ98Layout.key(5, 1), let lAlt = YZ98Layout.key(5, 2), let rAlt = YZ98Layout.key(5, 8) else { return }
        stage(lWin.id, Keycodes.modifier(0x04))
        stage(lAlt.id, Keycodes.modifier(0x08))
        stage(rAlt.id, Keycodes.modifier(0x80))
    }
}

final class LightingState: ObservableObject {
    @Published var brightness: Double = 0
    @Published var speed: Double = 0
}

final class PerKeyState: ObservableObject {
    @Published var colours: [RGB] = []
    @Published var brush: Color = .white
    @Published var brightness: Double = Double(LED.maxBrightness)
    @Published var dirty: Bool = false
}

final class RemapState: ObservableObject {
    @Published var layer: Int = 0
    @Published var staged: [Int: Keycodes.Code] = [:]
    @Published var selected: KeyCap? = nil
    @Published var search: String = ""
}

final class HitTracker: ObservableObject {
    var last: Int?
}

// MARK: - Live lighting

struct LiveView: View {
    @ObservedObject var kb: KeyboardModel
    @ObservedObject var live: LiveEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("The four keys under the decal (Home, End, PgUp, PgDn) light up while something below is happening, in this order of priority. The rest of the board keeps your saved lighting. These run while the app is open, including from the menu bar after you close this window.")
                .font(.callout).foregroundColor(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Zoom mute light: red while muted, green while unmuted", isOn: $live.zoomEnabled)
                    Text(zoomStatus).font(.callout).foregroundColor(.secondary)
                    if live.zoom == .noPermission {
                        Button("Open Accessibility settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                    Button("Preview (6 s)") { live.runPreview(.zoom) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Meeting alert: a blue sweep from 1 minute before a meeting until 2 minutes after it starts", isOn: $live.meetingEnabled)
                    Text(meetingStatus).font(.callout).foregroundColor(.secondary)
                    if live.calendarAccess == false {
                        Button("Open Calendar privacy settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                        }
                    }
                    Button("Preview (10 s)") { live.runPreview(.countdown) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
            }

            Toggle("Other call apps: pulse purple while any app uses the mic or camera (mute state unknown)", isOn: $live.onAirEnabled)
            Text("Mic: \(live.micInUse ? "in use" : "off")  ·  Camera: \(live.cameraInUse ? "in use" : "off")")
                .font(.callout).foregroundColor(.secondary)

            Toggle("Launch at login (so the decal works without opening the app)", isOn: Binding(get: { live.launchAtLogin }, set: { live.launchAtLogin = $0 }))

            Text("Decal now: \(live.showing)").font(.headline)
            Spacer()
        }
        .padding()
    }

    private var zoomStatus: String {
        guard live.zoomEnabled else { return "Off" }
        switch live.zoom {
        case .notRunning: return "Zoom isn't running."
        case .noPermission: return "Needs Accessibility permission to read Zoom's mute button. Allow YunziiControl in Privacy & Security → Accessibility."
        case .idle: return "Zoom is open, not in a meeting."
        case .muted: return "In a meeting: muted"
        case .live: return "In a meeting: unmuted"
        }
    }

    private var meetingStatus: String {
        guard live.meetingEnabled else { return "Off" }
        switch live.calendarAccess {
        case nil: return "Waiting for Calendar access…"
        case false?: return "No Calendar access. Allow YunziiControl in Privacy & Security → Calendars."
        default:
            guard let m = live.nextMeeting else { return "No meetings in the next 6 hours (reads the macOS Calendar app)." }
            return "Next: \(m.title) at \(m.start.formatted(date: .omitted, time: .shortened))"
        }
    }
}

struct MenuBarContent: View {
    @ObservedObject var kb: KeyboardModel
    @ObservedObject var live: LiveEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(kb.status == .ready ? "\(kb.modelName) connected" : "Keyboard not connected")
        Text("Decal: \(live.showing)")
        Divider()
        Toggle("Zoom mute light", isOn: $live.zoomEnabled)
        Toggle("Meeting alert", isOn: $live.meetingEnabled)
        Toggle("Other call apps", isOn: $live.onAirEnabled)
        Divider()
        Button("Open Yunzii Control…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit") { NSApp.terminate(nil) }
    }
}

// MARK: - Top row (Win-mode Mac layout)

struct TopRowView: View {
    @ObservedObject var kb: KeyboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("In Mac mode the keyboard uses a built-in layout where the top row is always media keys. To choose F1–F12 instead, set the switch to **Win**: the app writes a Mac-style layout for Win mode (Win key → ⌥ Option, Alt keys → ⌘ Command) plus your top-row choice. It's saved on the keyboard and works without the app running.")
                .font(.callout).foregroundColor(.secondary)

            if kb.macMode {
                Label("The switch is on Mac, so these settings are saved but won't take effect until you flip it to Win.", systemImage: "info.circle")
                    .font(.callout)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.18)))
            }

            Picker("Top row sends", selection: Binding(
                get: { kb.topRowFKeysFirst ?? false },
                set: { kb.setTopRow(fKeysFirst: $0) }
            )) {
                Text("Media keys (hold Fn for F1–F12)").tag(false)
                Text("F1–F12 (hold Fn for media)").tag(true)
            }
            .pickerStyle(.radioGroup)
            .disabled(kb.busy)

            if kb.topRowFKeysFirst == nil {
                HStack {
                    Text("Win mode isn't set up for Mac yet.").foregroundColor(.orange)
                    Button("Set up (media keys first)") { kb.setTopRow(fKeysFirst: false) }.disabled(kb.busy)
                }
            }

            GroupBox("Media functions") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(0..<12, id: \.self) { i in
                        VStack(spacing: 2) {
                            Text("F\(i + 1)").font(.caption.bold())
                            Text(TopRow.macMediaNames[i]).font(.caption2).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                    }
                }
                .padding(4)
            }

            HStack {
                Button("Restore original key table…") {
                    let a = NSAlert()
                    a.messageText = "Restore the key table from when the app first saw this keyboard?"
                    a.informativeText = "Win mode goes back to its Windows layout (Win/Alt keys and the original Fn shortcuts). Mac mode is never affected."
                    a.addButton(withTitle: "Restore")
                    a.addButton(withTitle: "Cancel")
                    if a.runModal() == .alertFirstButtonReturn { kb.restoreKeyTable() }
                }
                .disabled(kb.busy || kb.original == nil)
                Spacer()
            }
            Spacer()
        }
        .padding()
    }
}
