
import AppKit
import SwiftUI

@main
struct CogiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let clipboardMonitor = ClipboardMonitor()
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboardMonitor.start()
        menuBarController = MenuBarController(clipboardMonitor: clipboardMonitor)
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stop()
        menuBarController?.stop()
    }
}
