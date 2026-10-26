import AppKit
import ApplicationServices
import CoreAudio
import CoreMediaIO
import EventKit
import Foundation
import ServiceManagement

/// Drives the 4 LEDs under the decal (Home, End, PgUp, PgDn) with live frames.
/// When nothing needs showing it stops sending, and the keyboard falls back to its saved lighting.
final class LiveEngine: ObservableObject {
    static let decal = [15 * 6, 16 * 6, 17 * 6, 18 * 6]

    @Published var zoomEnabled: Bool { didSet { UserDefaults.standard.set(zoomEnabled, forKey: "live.zoom"); if zoomEnabled { requestAccessibility() } } }
    @Published var onAirEnabled: Bool { didSet { UserDefaults.standard.set(onAirEnabled, forKey: "live.otherCalls") } }
    @Published var meetingEnabled: Bool { didSet { UserDefaults.standard.set(meetingEnabled, forKey: "live.meeting"); if meetingEnabled { requestCalendar() } } }

    @Published private(set) var micInUse = false
    @Published private(set) var cameraInUse = false
    @Published private(set) var zoom: ZoomState = .notRunning
    @Published private(set) var nextMeeting: (title: String, start: Date)?
    @Published private(set) var calendarAccess: Bool?
    @Published private(set) var showing = "Nothing"

    private let kb: KeyboardModel
    private let store = EKEventStore()
    private var preview: (kind: Preview, until: Date)?
    private var cometPhase = 0.0
    private var lastRender = Date()
    private var tick: Timer?
    private var sensors: Timer?
    private var calendarTimer: Timer?

    enum Preview { case zoom, countdown }

    enum ZoomState: Equatable {
        case notRunning, noPermission, idle, muted, live
    }

    private let zoomQueue = DispatchQueue(label: "yunzii.zoom")

    init(kb: KeyboardModel) {
        self.kb = kb
        zoomEnabled = UserDefaults.standard.object(forKey: "live.zoom") as? Bool ?? true
        onAirEnabled = UserDefaults.standard.object(forKey: "live.otherCalls") as? Bool ?? false
        meetingEnabled = UserDefaults.standard.object(forKey: "live.meeting") as? Bool ?? false
    }

    func start() {
        sensors = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.readSensors() }
        tick = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in self?.render() }
        calendarTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refreshMeetings() }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.refreshMeetings() }
        readSensors()
        if meetingEnabled { requestCalendar() }
        if zoomEnabled { requestAccessibility() }
    }

    func runPreview(_ kind: Preview) {
        preview = (kind, Date().addingTimeInterval(kind == .zoom ? 6 : 10))
    }

    // MARK: Rendering

    private func render() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastRender), 0.2)
        lastRender = now
        if let p = preview, p.until < now { preview = nil }
        let decalColours: [RGB]?
        let label: String
        if let p = preview {
            let left = p.until.timeIntervalSince(now)
            switch p.kind {
            case .zoom: (decalColours, label) = (left > 3 ? Self.solid(Self.muted) : Self.solid(Self.unmuted), "Preview: Zoom mute")
            case .countdown: (decalColours, label) = (meetingAlert(seconds: left > 3 ? (left - 3) / 7 * 60 : left - 3, dt: dt), "Preview: meeting alert")
            }
        } else if zoomEnabled && zoom == .muted {
            (decalColours, label) = (Self.solid(Self.muted), "Zoom: muted")
        } else if zoomEnabled && zoom == .live {
            (decalColours, label) = (Self.solid(Self.unmuted), "Zoom: unmuted")
        } else if meetingEnabled, let m = nextMeeting, let c = meetingAlert(seconds: m.start.timeIntervalSince(now), dt: dt) {
            (decalColours, label) = (c, "Meeting alert: \(m.title)")
        } else if onAirEnabled && (micInUse || cameraInUse) {
            (decalColours, label) = (otherCall(now), "Other call: mic/camera in use")
        } else {
            (decalColours, label) = (nil, "Nothing")
        }
        if showing != label { showing = label }
        guard let d = decalColours else { return }
        var frame = kb.liveBase()
        for (i, led) in Self.decal.enumerated() { frame[led] = d[i] }
        kb.sendLiveFrame(frame)
    }

    static let muted = RGB(r: 255, g: 0, b: 0)
    static let unmuted = RGB(r: 0, g: 255, b: 0)

    private static func solid(_ c: RGB) -> [RGB] { Array(repeating: c, count: 4) }

    private func otherCall(_ now: Date) -> [RGB] {
        let pulse = 0.6 + 0.4 * sin(now.timeIntervalSinceReferenceDate * .pi)
        return Self.solid(RGB(r: UInt8(170 * pulse), g: 0, b: UInt8(255 * pulse)))
    }

    /// From 1 minute before a meeting until 2 minutes after it starts: a blue comet bouncing back and forth.
    private func meetingAlert(seconds: Double, dt: Double) -> [RGB]? {
        guard seconds <= 60, seconds >= -120 else { return nil }
        cometPhase = (cometPhase + dt * 2.1).truncatingRemainder(dividingBy: 2)
        return Self.comet(phase: cometPhase, hue: 0.58)
    }

    /// One bright head bouncing across the 4 segments with a soft falloff on either side.
    private static func comet(phase: Double, hue: Double) -> [RGB] {
        let head = (phase < 1 ? phase : 2 - phase) * 3
        let c = NSColor(calibratedHue: hue, saturation: 1, brightness: 1, alpha: 1).usingColorSpace(.deviceRGB) ?? .white
        return (0..<4).map { i in
            let k = pow(max(0, 1 - abs(Double(i) - head) / 1.4), 2)
            return RGB(r: UInt8(c.redComponent * 255 * k), g: UInt8(c.greenComponent * 255 * k), b: UInt8(c.blueComponent * 255 * k))
        }
    }

    // MARK: Mic and camera

    private func readSensors() {
        let mic = Self.anyMicRunning()
        let cam = Self.anyCameraRunning()
        if mic != micInUse { micInUse = mic }
        if cam != cameraInUse { cameraInUse = cam }
        guard zoomEnabled else { if zoom != .notRunning { zoom = .notRunning }; return }
        zoomQueue.async {
            let z = Self.readZoom()
            DispatchQueue.main.async { if z != self.zoom { self.zoom = z } }
        }
    }

    // MARK: Zoom mute state

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Zoom's Meeting menu shows "Mute audio" while you're live and "Unmute audio" while muted.
    private static func readZoom() -> ZoomState {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").first else { return .notRunning }
        guard AXIsProcessTrusted() else { return .noPermission }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.5)
        guard let bar: AXUIElement = attribute(ax, kAXMenuBarAttribute) else { return .idle }
        for item in children(bar) where title(item)?.caseInsensitiveCompare("Meeting") == .orderedSame {
            for menu in children(item) {
                for entry in children(menu) {
                    let t = title(entry)?.lowercased() ?? ""
                    if t.hasPrefix("unmute audio") { return .muted }
                    if t.hasPrefix("mute audio") { return .live }
                }
            }
        }
        return .idle
    }

    private static func attribute<T>(_ el: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] { attribute(el, kAXChildrenAttribute) ?? [] }
    private static func title(_ el: AXUIElement) -> String? { attribute(el, kAXTitleAttribute) }

    private static func anyMicRunning() -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return false }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return false }
        for id in ids {
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var ssize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &ssize) == noErr, ssize > 0 else { continue }
            var running = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var value: UInt32 = 0
            var vsize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &running, 0, nil, &vsize, &value) == noErr, value != 0 { return true }
        }
        return false
    }

    private static func anyCameraRunning() -> Bool {
        var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                             mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                             mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == 0 else { return false }
        for id in ids {
            var running = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var value: UInt32 = 0
            var vused: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &vused, &value) == 0, value != 0 { return true }
        }
        return false
    }

    // MARK: Calendar

    func requestCalendar() {
        let done: (Bool, Error?) -> Void = { granted, _ in
            DispatchQueue.main.async {
                self.calendarAccess = granted
                self.refreshMeetings()
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: done)
        } else {
            store.requestAccess(to: .event, completion: done)
        }
    }

    private func refreshMeetings() {
        guard meetingEnabled, calendarAccess == true else { nextMeeting = nil; return }
        let now = Date()
        let events = store.events(matching: store.predicateForEvents(withStart: now.addingTimeInterval(-180), end: now.addingTimeInterval(6 * 3600), calendars: nil))
        nextMeeting = events
            .filter { !$0.isAllDay && $0.availability != .free && $0.startDate > now.addingTimeInterval(-120) }
            .filter { $0.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined }
            .min { $0.startDate < $1.startDate }
            .map { ($0.title ?? "Meeting", $0.startDate) }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        }
    }
}
