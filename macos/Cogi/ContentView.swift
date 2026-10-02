import AppKit
import SwiftUI

// Search, selection scrolling and keyboard interaction follow Maccy's native UI
// patterns: https://github.com/p0deje/Maccy (see Resources/Maccy-LICENSE.txt).
@MainActor
final class MenuSelection: ObservableObject {
    @Published var itemID: UUID?
    @Published var keyboardRevision = 0
}

struct ContentView: View {
    @ObservedObject var clipboardMonitor: ClipboardMonitor
    @ObservedObject var selection: MenuSelection
    let screenHeight: CGFloat
    let onHover: (DetectedClipboardItem?, NSView?) -> Void
    let onSearchFocus: (Bool) -> Void
    let onSearch: (String) -> Void
    let onResize: (CGFloat) -> Void
    let onPreferences: () -> Void
    let onAbout: () -> Void
    let onClear: () -> Void

    @State private var search = ""
    @FocusState private var searchFocused: Bool

    private var items: [DetectedClipboardItem] {
        let filtered = clipboardMonitor.recentItems.filter {
            search.isEmpty || $0.text.localizedCaseInsensitiveContains(search)
        }
        return filtered.filter(\.isPinned) + filtered.filter { !$0.isPinned }
    }

    private var firstUnpinnedID: UUID? {
        guard items.contains(where: \.isPinned) else { return nil }
        return items.first(where: { !$0.isPinned })?.id
    }

    private var panelHeight: CGFloat {
        min(max(CGFloat(max(items.count, 1)) * 30 + 178 + (firstUnpinnedID == nil ? 0 : 9), screenHeight * 0.25), screenHeight * 0.75)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Type to search…", text: $search)
                    .textFieldStyle(.plain)
                    .disableAutocorrection(true)
                    .lineLimit(1)
                    .focused($searchFocused)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(7)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))

            ScrollViewReader { proxy in
              ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if items.isEmpty {
                        Text(search.isEmpty ? "Copy plain text to see it here." : "No matching clipboard text.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(items) { item in
                            if item.id == firstUnpinnedID {
                                Divider().padding(.vertical, 4)
                            }
                            ClipboardRow(item: item, monitor: clipboardMonitor, selection: selection, onHover: onHover)
                                .id(item.id)
                        }
                    }
                }
              }
              .onChange(of: selection.keyboardRevision) { _, _ in
                  searchFocused = false
                  if let id = selection.itemID { proxy.scrollTo(id) }
              }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            VStack(spacing: 0) {
                footer("Clear All", hint: "⇧⌘⌫", action: onClear)
                    .disabled(clipboardMonitor.recentItems.isEmpty)
                footer("Preferences…", hint: "⌘,", action: onPreferences)
                footer("About", hint: "", action: onAbout)
                footer("Quit", hint: "⌘Q") { NSApplication.shared.terminate(nil) }
            }
        }
        .font(.system(size: 13))
        .padding(10)
        .frame(width: 440, height: panelHeight)
        .onAppear {
            searchFocused = true
            onResize(panelHeight)
        }
        .onChange(of: panelHeight) { _, height in onResize(height) }
        .onChange(of: searchFocused) { _, focused in onSearchFocus(focused) }
        .onChange(of: search) { _, query in onSearch(query) }
    }

    private func footer(_ title: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(hint).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .frame(height: 25)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ClipboardRow: View {
    let item: DetectedClipboardItem
    @ObservedObject var monitor: ClipboardMonitor
    @ObservedObject var selection: MenuSelection
    let onHover: (DetectedClipboardItem?, NSView?) -> Void

    private var highlighted: Bool { selection.itemID == item.id }

    private var preview: String {
        let prefix = item.text.prefix(80)
        let singleLine = prefix
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ↵ ")
            .replacingOccurrences(of: "\t", with: " ⇥ ")
        let label = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = label.isEmpty ? "(Whitespace text)" : label
        return item.text.dropFirst(80).isEmpty ? visible : visible + "…"
    }

    var body: some View {
        HStack(spacing: 6) {
            Button { monitor.copy(item) } label: {
                Text(verbatim: preview)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .accessibilityLabel("Pinned")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .background(highlighted ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        .background(RowHoverAnchor { entered, view in
            onHover(entered ? item : nil, entered ? view : nil)
        })
    }
}

private struct RowHoverAnchor: NSViewRepresentable {
    let onHover: (Bool, NSView) -> Void

    func makeNSView(context: Context) -> HoverView {
        let view = HoverView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: HoverView, context: Context) {
        nsView.onHover = onHover
    }

    final class HoverView: NSView {
        var onHover: ((Bool, NSView) -> Void)?
        private var area: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
            addTrackingArea(area)
            self.area = area
        }

        override func mouseEntered(with event: NSEvent) { onHover?(true, self) }
        override func mouseExited(with event: NSEvent) { onHover?(false, self) }
    }
}

struct ClipboardPreview: View {
    let item: DetectedClipboardItem
    let textHeight: CGFloat
    let panelHeight: CGFloat
    let onHover: (Bool) -> Void

    var body: some View {
        Group {
            if textHeight <= 0 {
                // On unusually small screens, keep both text and details reachable.
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        fullText
                        Divider()
                        ClipboardPreviewDetails(item: item)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ScrollView {
                        fullText
                    }
                    .frame(height: textHeight)
                    Divider()
                    ClipboardPreviewDetails(item: item)
                }
            }
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(width: 340, height: panelHeight)
        .background(.regularMaterial)
        .onHover(perform: onHover)
    }

    private var fullText: some View {
        Text(verbatim: item.text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ClipboardPreviewDetails: View {
    let item: DetectedClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Application: \(item.foregroundApplicationName ?? "Unknown")")
                .help("Foreground application when the clipboard change was detected; macOS does not identify the pasteboard owner.")
            Text("Last copied: \(item.lastCopiedAt.formatted(date: .abbreviated, time: .standard))")
            Text(item.isPinned ? "Pinned · Press ⌘P to unpin · Press ⌘⌫ to delete" : "Press ⌘P to pin · Press ⌘⌫ to delete")
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
