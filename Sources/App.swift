import AppKit
import SwiftUI

/// One keyboard connection and live engine shared by the window and the menu bar.
enum AppState {
    static let kb = KeyboardModel()
    static let live = LiveEngine(kb: kb)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.kb.start()
        AppState.live.start()
    }

    // Keep running from the menu bar so the decal lighting keeps working.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct YunziiControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("Yunzii Control", id: "main") {
            ContentView(kb: AppState.kb, live: AppState.live)
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra("Yunzii Control", systemImage: "keyboard") {
            MenuBarContent(kb: AppState.kb, live: AppState.live)
        }
    }
}
