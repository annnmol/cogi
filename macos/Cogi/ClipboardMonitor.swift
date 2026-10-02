import AppKit
import Combine

struct DetectedClipboardItem: Identifiable {
    let id = UUID()
    let text: String
    let detectedAt: Date
    var lastCopiedAt: Date
    let foregroundApplicationName: String?
    let characterCount: Int
    var copyCount = 1
    var isPinned = false

    init(text: String, foregroundApplicationName: String?) {
        self.text = text
        let now = Date()
        detectedAt = now
        lastCopiedAt = now
        self.foregroundApplicationName = foregroundApplicationName
        characterCount = text.count
    }
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

        var items = recentItems
        var existingItem = items.remove(at: index)
        existingItem.lastCopiedAt = Date()
        existingItem.copyCount += 1
        items.insert(existingItem, at: 0)
        recentItems = items
    }

    func togglePin(_ item: DetectedClipboardItem) {
        guard let index = recentItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard recentItems[index].isPinned || recentItems.filter(\.isPinned).count < 5 else {
            NSSound.beep()
            return
        }
        recentItems[index].isPinned.toggle()
    }

    func delete(_ item: DetectedClipboardItem) {
        recentItems.removeAll { $0.id == item.id }
    }

    func clearAll() {
        recentItems.removeAll()
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

        var items = recentItems
        let application = NSWorkspace.shared.frontmostApplication
        let applicationName = application?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? nil : application?.localizedName
        items.insert(DetectedClipboardItem(text: text, foregroundApplicationName: applicationName), at: 0)
        if items.count > 40,
           let index = items.lastIndex(where: { !$0.isPinned }) {
            items.remove(at: index)
        }
        recentItems = items

        // Each observed copy is distinct, even when the text matches a previous copy.
        // Menu copies account for their own change count and do not reach this path.
        #if DEBUG
        print("[Cogi] Clipboard text: \(text.debugDescription)")
        #endif
    }
}
