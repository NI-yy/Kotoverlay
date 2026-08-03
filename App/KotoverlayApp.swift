import AppKit
import SwiftUI

@main
struct KotoverlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Kotoverlay", systemImage: "character.bubble") {
            MenuBarContent(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsContent(model: appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.refreshReadiness()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.pause()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
