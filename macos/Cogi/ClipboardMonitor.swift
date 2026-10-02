import AppKit
import Combine

struct DetectedClipboardItem: Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
final class ClipboardMonitor: NSObject, ObservableObject {
    @Published private(set) var recentItems: [DetectedClipboardItem] = []

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = 0
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }

        // Observe changes made after launch without logging existing clipboard text.
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(checkForChanges),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func copy(_ item: DetectedClipboardItem) {
        guard let index = recentItems.firstIndex(where: { $0.id == item.id }) else { return }

        let changeCount = pasteboard.changeCount
        let currentText = pasteboard.string(forType: .string)
        let alreadyCopied = pasteboard.changeCount == changeCount && currentText == item.text

        if !alreadyCopied {
            let ownChangeCount = pasteboard.clearContents()
            guard pasteboard.setString(item.text, forType: .string) else {
                NSSound.beep()
                return
            }

            // Suppress only our own pasteboard change. If another app has taken
            // ownership since the write, leave its change for the next poll.
            if pasteboard.changeCount == ownChangeCount {
                lastChangeCount = ownChangeCount
            }
        }

        let existingItem = recentItems.remove(at: index)
        recentItems.insert(existingItem, at: 0)
    }

    @objc private func checkForChanges() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }

        let text = pasteboard.string(forType: .string)

        // Another application can change the pasteboard while text is being read.
        // Retry on the next tick instead of associating text with the wrong change.
        guard pasteboard.changeCount == changeCount else { return }
        lastChangeCount = changeCount

        guard let text, !text.isEmpty else { return }

        recentItems.insert(DetectedClipboardItem(text: text), at: 0)
        if recentItems.count > 10 {
            recentItems.removeLast(recentItems.count - 10)
        }

        // Each observed copy is distinct, even when the text matches a previous copy.
        // Menu copies account for their own change count and do not reach this path.
        #if DEBUG
        print("[Cogi] Clipboard text: \(text.debugDescription)")
        #endif
    }
}
