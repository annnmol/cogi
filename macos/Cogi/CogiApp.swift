
import AppKit
import SwiftUI

@main
struct CogiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Cogi", systemImage: "doc.on.clipboard") {
            ContentView(clipboardMonitor: appDelegate.clipboardMonitor)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let clipboardMonitor = ClipboardMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboardMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stop()
    }
}
