import AppKit
import Combine
import SwiftUI

// Native focus, bounded sizing, selection and cancellable preview patterns are
// adapted from Maccy: https://github.com/p0deje/Maccy. MIT notice is bundled in
// Resources/Maccy-LICENSE.txt. Cogi's pasteboard monitor remains independent.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let clipboardMonitor: ClipboardMonitor
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var previewPanel: NSPanel?
    private var previewItemID: UUID?
    private var hoveredItemID: UUID?
    private weak var hoverAnchor: NSView?
    private let selection = MenuSelection()
    private var searchQuery = ""
    private var keyboardNavigating = false
    private var searchFocused = false
    private var previewCloseWork: DispatchWorkItem?
    private var previewOpenWork: DispatchWorkItem?
    private var localEvents: Any?
    private var outsideEvents: Any?
    private var resignObserver: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var isTrackingMenu = false
    private var itemsSubscription: AnyCancellable?
    private var preferencesWindow: NSWindow?
    private var aboutWindow: NSWindow?

    init(clipboardMonitor: ClipboardMonitor) {
        self.clipboardMonitor = clipboardMonitor
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Cogi")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "Cogi"
        }
        // Explicit dismissal keeps the hover preview interactive while the main
        // popover is open, and closes both when the user clicks elsewhere.
        popover.behavior = .applicationDefined
        popover.delegate = self
        localEvents = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handle(event) == nil
            }
            return consumed ? nil : event
        }
        outsideEvents = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePopover() }
        }
        menuObservers = [
            NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isTrackingMenu = true }
            },
            NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isTrackingMenu = false }
            }
        ]
        itemsSubscription = clipboardMonitor.$recentItems.sink { [weak self] items in
            guard let self else { return }
            if let id = self.previewItemID {
                if let item = items.first(where: { $0.id == id }) {
                    self.updatePreview(item)
                } else {
                    self.hidePreview()
                }
            }
            if let id = self.hoveredItemID, !items.contains(where: { $0.id == id }) {
                self.hoveredItemID = nil
            }
            if let id = self.selection.itemID, !items.contains(where: { $0.id == id }) {
                self.selection.itemID = nil
            }
        }
    }

    func stop() {
        closePopover()
        if let localEvents { NSEvent.removeMonitor(localEvents) }
        if let outsideEvents { NSEvent.removeMonitor(outsideEvents) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        menuObservers.removeAll()
        localEvents = nil
        outsideEvents = nil
        resignObserver = nil
        itemsSubscription = nil
        preferencesWindow?.close()
        aboutWindow?.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
            return
        }
        guard let button = statusItem.button else { return }
        searchFocused = false
        searchQuery = ""
        keyboardNavigating = false
        selection.itemID = filteredItems.first?.id
        hoveredItemID = nil
        let screenHeight = (button.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let content = ContentView(
            clipboardMonitor: clipboardMonitor,
            selection: selection,
            screenHeight: screenHeight,
            onHover: { [weak self] item, anchor in self?.hover(item, anchor: anchor) },
            onSearchFocus: { [weak self] focused in self?.searchFocused = focused },
            onSearch: { [weak self] query in
                guard let self else { return }
                self.searchQuery = query
                self.hidePreview()
                self.selection.itemID = self.filteredItems.first?.id
            },
            onResize: { [weak self] height in self?.popover.contentSize = NSSize(width: 440, height: height) },
            onPreferences: { [weak self] in self?.openAuxiliaryWindow(preferences: true) },
            onAbout: { [weak self] in self?.openAuxiliaryWindow(preferences: false) },
            onClear: { [weak self] in self?.clearAll() }
        )
        popover.contentViewController = NSHostingController(rootView: content)
        let items = filteredItems
        let separatorHeight: CGFloat = items.contains(where: \.isPinned) && items.contains(where: { !$0.isPinned }) ? 9 : 0
        let initialHeight = min(max(max(items.reduce(0) { $0 + $1.rowHeight }, 30) + 178 + separatorHeight, screenHeight * 0.25), screenHeight * 0.75)
        popover.contentSize = NSSize(width: 440, height: initialHeight)
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.isHighlighted = true
        popover.contentViewController?.view.window?.makeKey()
        popover.contentViewController?.view.window?.acceptsMouseMovedEvents = true
    }

    private func closePopover() {
        hidePreview()
        hoveredItemID = nil
        hoverAnchor = nil
        statusItem.button?.isHighlighted = false
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        hidePreview()
        hoveredItemID = nil
        hoverAnchor = nil
        statusItem.button?.isHighlighted = false
    }

    private func hover(_ item: DetectedClipboardItem?, anchor: NSView?) {
        guard popover.isShown else { return }
        previewOpenWork?.cancel()
        guard let item, let anchor else {
            schedulePreviewClose()
            return
        }
        previewCloseWork?.cancel()
        hoveredItemID = item.id
        hoverAnchor = anchor
        guard !keyboardNavigating else { return }
        selection.itemID = item.id
        let work = DispatchWorkItem { [weak self, weak anchor] in
            MainActor.assumeIsolated {
                guard let self, let anchor, self.popover.isShown,
                      let currentItem = self.clipboardMonitor.recentItems.first(where: { $0.id == item.id }) else { return }
                self.showPreview(currentItem, anchor: anchor)
            }
        }
        previewOpenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func showPreview(_ item: DetectedClipboardItem, anchor: NSView) {
        guard let window = anchor.window else { return }
        previewItemID = item.id
        if previewPanel == nil {
            let panel = PreviewPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .popUpMenu
            panel.hasShadow = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hidesOnDeactivate = true
            previewPanel = panel
        }
        updatePreview(item)
        guard let panel = previewPanel else { return }
        let anchorFrame = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let mainFrame = window.frame
        let leftX = mainFrame.minX - panel.frame.width - 8
        let desiredX = leftX >= screen.minX ? leftX : mainFrame.maxX + 8
        let x = max(screen.minX, min(desiredX, screen.maxX - panel.frame.width))
        let y = max(screen.minY, min(anchorFrame.maxY - panel.frame.height, screen.maxY - panel.frame.height))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFront(nil)
    }

    private func updatePreview(_ item: DetectedClipboardItem) {
        guard let panel = previewPanel else { return }
        let screen = popover.contentViewController?.view.window?.screen ?? panel.screen ?? NSScreen.main
        let maximumHeight = (screen?.visibleFrame.height ?? 800) * 0.4
        let metadata = NSHostingView(rootView: ClipboardPreviewDetails(item: item)
            .frame(width: 312)
            .fixedSize(horizontal: false, vertical: true))
        let metadataHeight = ceil(metadata.fittingSize.height)
        let naturalTextHeight: CGFloat
        if let image = item.image {
            naturalTextHeight = 312 * CGFloat(image.height) / CGFloat(image.width)
        } else {
            let font = NSFont.systemFont(ofSize: 12)
            let text = NSAttributedString(string: item.text, attributes: [.font: font])
            naturalTextHeight = ceil(text.boundingRect(
                with: NSSize(width: 312, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height) + 2
        }
        // Padding, two stack spacings and the native divider are real content;
        // there is no minimum preview-window height.
        let detailsHeight = metadataHeight + 28 + 20 + 1
        let height = min(naturalTextHeight + detailsHeight, maximumHeight)
        let availableTextHeight = max(0, height - detailsHeight)
        let oldTop = panel.frame.maxY
        panel.contentView = NSHostingView(rootView: ClipboardPreview(item: item, textHeight: availableTextHeight, panelHeight: height) { [weak self] entered in
            if entered {
                self?.previewCloseWork?.cancel()
            } else {
                self?.schedulePreviewClose()
            }
        })
        panel.setContentSize(NSSize(width: 340, height: height))
        if panel.isVisible, let screen {
            let y = max(screen.visibleFrame.minY, min(oldTop - height, screen.visibleFrame.maxY - height))
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: y))
        }
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 8
        panel.contentView?.layer?.masksToBounds = true
    }

    private func schedulePreviewClose() {
        previewCloseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.hidePreview()
                self?.hoveredItemID = nil
            }
        }
        previewCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func hidePreview() {
        previewOpenWork?.cancel()
        previewOpenWork = nil
        previewCloseWork?.cancel()
        previewCloseWork = nil
        previewPanel?.orderOut(nil)
        previewItemID = nil
    }

    private func clearAll() {
        hidePreview()
        hoveredItemID = nil
        clipboardMonitor.clearAll()
        selection.itemID = nil
    }

    private var filteredItems: [DetectedClipboardItem] {
        let filtered = clipboardMonitor.recentItems.filter {
            $0.matchesSearch(searchQuery)
        }
        return filtered.filter(\.isPinned) + filtered.filter { !$0.isPinned }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard !isTrackingMenu else { return event }
        if !popover.isShown {
            guard event.type == .keyDown, let window = event.window,
                  window === preferencesWindow || window === aboutWindow else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if modifiers == .command, event.keyCode == 12 {
                NSApplication.shared.terminate(nil)
                return nil
            }
            if modifiers == .command, event.keyCode == 43 {
                openAuxiliaryWindow(preferences: true)
                return nil
            }
            return event
        }
        if event.type == .mouseMoved {
            let wasKeyboardNavigating = keyboardNavigating
            keyboardNavigating = false
            if let hoveredItemID {
                selection.itemID = hoveredItemID
                if wasKeyboardNavigating, let anchor = hoverAnchor,
                   let item = clipboardMonitor.recentItems.first(where: { $0.id == hoveredItemID }) {
                    hover(item, anchor: anchor)
                }
            }
            return event
        }
        if event.type != .keyDown {
            let mainWindow = popover.contentViewController?.view.window
            if event.window !== mainWindow && event.window !== previewPanel && event.window !== statusItem.button?.window {
                closePopover()
            }
            return event
        }
        // Respect input-method composition before consuming navigation keys.
        if let input = event.window?.firstResponder as? NSTextInputClient, input.hasMarkedText() {
            return event
        }
        if event.keyCode == 53 {
            closePopover()
            return nil
        }
        if event.window === previewPanel, event.window?.firstResponder is NSTextView,
           !event.modifierFlags.contains(.command) {
            return event
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.isDisjoint(with: [.command, .option, .control, .shift]),
           event.keyCode == 125 || event.keyCode == 126 {
            let items = filteredItems
            guard !items.isEmpty else { return event }
            let index = items.firstIndex(where: { $0.id == selection.itemID })
            let next = event.keyCode == 125 ? min((index ?? -1) + 1, items.count - 1) : max((index ?? items.count) - 1, 0)
            keyboardNavigating = true
            hidePreview()
            selection.itemID = items[next].id
            selection.keyboardRevision += 1
            return nil
        }
        if modifiers.isDisjoint(with: [.command, .option, .control, .shift]),
           event.keyCode == 36 || event.keyCode == 76,
           let item = filteredItems.first(where: { $0.id == selection.itemID }) {
            clipboardMonitor.copy(item)
            closePopover()
            return nil
        }
        guard modifiers.contains(.command), !modifiers.contains(.option), !modifiers.contains(.control) else { return event }
        if event.keyCode == 12, !modifiers.contains(.shift) {
            NSApplication.shared.terminate(nil)
            return nil
        }
        if event.keyCode == 43, !modifiers.contains(.shift) {
            openAuxiliaryWindow(preferences: true)
            return nil
        }
        if event.keyCode == 51, modifiers.contains(.shift) {
            clearAll()
            return nil
        }
        // A deliberate hover targets row actions even if search still has focus.
        // Otherwise retain the search field's native text-deletion shortcut.
        let pointerOnRow: Bool
        if let anchor = hoverAnchor, let window = anchor.window {
            let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            pointerOnRow = anchor.visibleRect.contains(anchor.convert(point, from: nil))
        } else {
            pointerOnRow = false
        }
        let editingText = event.window?.firstResponder is NSTextView
        guard !(event.window === previewPanel && editingText),
              !searchFocused || pointerOnRow,
              !editingText || (searchFocused && pointerOnRow) else { return event }
        guard let id = selection.itemID, let item = clipboardMonitor.recentItems.first(where: { $0.id == id }), !modifiers.contains(.shift) else { return event }
        if event.keyCode == 35 {
            clipboardMonitor.togglePin(item)
            return nil
        }
        if event.keyCode == 51 {
            clipboardMonitor.delete(item)
            return nil
        }
        return event
    }

    private func openAuxiliaryWindow(preferences: Bool) {
        closePopover()
        let existing = preferences ? preferencesWindow : aboutWindow
        let window: NSWindow
        if let existing {
            window = existing
        } else {
            let size = preferences ? NSSize(width: 560, height: 300) : NSSize(width: 320, height: 120)
            window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = preferences ? "Cogi Preferences" : "About Cogi"
            window.isReleasedWhenClosed = false
            if preferences {
                window.contentViewController = PreferencesContent.makeViewController()
                window.contentMinSize = NSSize(width: 560, height: 260)
                window.toolbar?.displayMode = .iconAndLabel
            } else {
                window.contentView = NSHostingView(rootView: Text("About test window.").padding(24).frame(maxWidth: .infinity, maxHeight: .infinity))
            }
            window.center()
            if preferences { preferencesWindow = window } else { aboutWindow = window }
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
