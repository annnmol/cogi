import AppKit
import Combine

struct DetectedClipboardItem: Identifiable, Sendable {
    let id: UUID
    let text: String
    let detectedAt: Date
    var lastCopiedAt: Date
    let foregroundApplicationName: String?
    let characterCount: Int
    var copyCount = 1
    var isPinned = false
    let image: TemporaryClipboardImage?

    init(text: String = "", image: TemporaryClipboardImage? = nil, foregroundApplicationName: String?, copiedAt: Date = Date()) {
        id = UUID()
        self.text = text
        detectedAt = copiedAt
        lastCopiedAt = copiedAt
        self.foregroundApplicationName = foregroundApplicationName
        characterCount = text.count
        self.image = image
    }

    init(saved: PersistedClipboardItem) {
        id = saved.id
        text = saved.text
        detectedAt = saved.detectedAt
        lastCopiedAt = saved.lastCopiedAt
        foregroundApplicationName = saved.foregroundApplicationName
        characterCount = saved.characterCount
        copyCount = saved.copyCount
        isPinned = saved.isPinned
        image = nil
    }

    var rowHeight: CGFloat { image == nil ? 26 : 52 }

    func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if image != nil {
            return "Image \(foregroundApplicationName ?? "")".localizedCaseInsensitiveContains(query)
        }
        return text.localizedCaseInsensitiveContains(query)
    }
}

@MainActor
final class ClipboardMonitor: NSObject, ObservableObject {
    @Published private(set) var recentItems: [DetectedClipboardItem] = [] {
        didSet {
            if hasLoadedHistory { historyStore.save(recentItems) }
        }
    }

    private let historyStore = ClipboardHistoryStore()
    private var hasLoadedHistory = false
    private var clearWhenLoaded = false
    private var isRunning = false
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = 0
    private var timer: Timer?
    private let imageQueue = DispatchQueue(label: "com.anmoltanwar.cogi.clipboard-images", qos: .utility)
    private var isProcessingImage = false
    private var imageGeneration = UUID()

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Observe changes made after launch without logging existing clipboard text.
        lastChangeCount = pasteboard.changeCount
        guard hasLoadedHistory else {
            historyStore.load { [weak self] items in
                Task { @MainActor in
                    guard let self, self.isRunning else { return }
                    self.recentItems = self.clearWhenLoaded ? [] : Self.restore(items)
                    self.hasLoadedHistory = true
                    if self.clearWhenLoaded {
                        self.clearWhenLoaded = false
                    }
                    self.startTimer()
                }
            }
            return
        }
        startTimer()
    }

    private func startTimer() {
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
        imageGeneration = UUID()
        isRunning = false
        timer?.invalidate()
        timer = nil
        historyStore.flush()
    }

    func copy(_ item: DetectedClipboardItem) {
        guard let index = recentItems.firstIndex(where: { $0.id == item.id }) else { return }

        let changeCount = pasteboard.changeCount
        let alreadyCopied: Bool
        if let image = item.image {
            let data = pasteboard.data(forType: NSPasteboard.PasteboardType(image.pasteboardType))
            alreadyCopied = pasteboard.changeCount == changeCount && data == image.data
        } else {
            let currentText = pasteboard.string(forType: .string)
            alreadyCopied = pasteboard.changeCount == changeCount && currentText == item.text
        }

        if !alreadyCopied {
            let ownChangeCount = pasteboard.clearContents()
            let written: Bool
            if let image = item.image {
                written = pasteboard.setData(image.data, forType: NSPasteboard.PasteboardType(image.pasteboardType))
            } else {
                written = pasteboard.setString(item.text, forType: .string)
            }
            guard written else {
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
        imageGeneration = UUID()
        guard hasLoadedHistory else {
            clearWhenLoaded = true
            historyStore.save([])
            return
        }
        recentItems.removeAll()
    }

    private static func restore(_ items: [PersistedClipboardItem]) -> [DetectedClipboardItem] {
        var seen = Set<UUID>()
        var pinnedCount = 0
        var restored: [DetectedClipboardItem] = []
        for saved in items {
            var item = DetectedClipboardItem(saved: saved)
            guard !item.text.isEmpty, seen.insert(item.id).inserted else { continue }
            if item.isPinned {
                pinnedCount += 1
                if pinnedCount > 5 { item.isPinned = false }
            }
            restored.append(item)
            if restored.count == 40 { break }
        }
        return restored
    }

    @objc private func checkForChanges() {
        guard !isProcessingImage else { return }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }

        let imageType = pasteboard.availableType(from: [.png, .tiff])
        let imageData = imageType.flatMap { pasteboard.data(forType: $0) }
        let text = imageType == nil ? pasteboard.string(forType: .string) : nil

        // Another application can change the pasteboard while content is read.
        // Retry on the next tick instead of associating content with the wrong change.
        guard pasteboard.changeCount == changeCount else { return }
        lastChangeCount = changeCount

        let application = NSWorkspace.shared.frontmostApplication
        let applicationName = application?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? nil : application?.localizedName
        if let imageType, let imageData {
            guard !imageData.isEmpty, imageData.count <= TemporaryClipboardImage.maximumDataSize else { return }
            let copiedAt = Date()
            let type = imageType.rawValue
            let generation = imageGeneration
            isProcessingImage = true
            imageQueue.async { [weak self] in
                let image = TemporaryClipboardImage.make(data: imageData, pasteboardType: type)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isProcessingImage = false
                    guard self.isRunning, self.imageGeneration == generation, let image else { return }
                    self.insert(DetectedClipboardItem(image: image, foregroundApplicationName: applicationName, copiedAt: copiedAt))
                }
            }
            return
        }
        guard let text, !text.isEmpty else { return }
        insert(DetectedClipboardItem(text: text, foregroundApplicationName: applicationName))

        #if DEBUG
        print("[Cogi] Clipboard text: \(text.debugDescription)")
        #endif
    }

    private func insert(_ item: DetectedClipboardItem) {
        var items = recentItems
        // Image preparation is asynchronous; a newer manual copy must remain
        // above an image captured before that copy.
        let insertionIndex = item.image == nil ? 0 : items.firstIndex(where: { $0.lastCopiedAt < item.lastCopiedAt }) ?? items.endIndex
        items.insert(item, at: insertionIndex)
        if items.count > 40,
           let index = items.lastIndex(where: { !$0.isPinned }) {
            items.remove(at: index)
        }
        var imageBytes = items.reduce(0) { $0 + ($1.image?.data.count ?? 0) }
        while imageBytes > TemporaryClipboardImage.maximumHistoryDataSize,
              let index = items.lastIndex(where: { $0.image != nil && !$0.isPinned }) {
            imageBytes -= items[index].image?.data.count ?? 0
            items.remove(at: index)
        }
        recentItems = items
    }
}
