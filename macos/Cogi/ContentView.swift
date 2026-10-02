
import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var clipboardMonitor: ClipboardMonitor

    var body: some View {
        Text("Monitoring clipboard")
        Divider()
        Text("Recent clipboard text")
        if clipboardMonitor.recentItems.isEmpty {
            Text("Copy plain text to see it here.")
        } else {
            ForEach(clipboardMonitor.recentItems) { item in
                Button {
                    clipboardMonitor.copy(item)
                } label: {
                    Text(verbatim: preview(for: item.text))
                }
            }
        }
        Divider()
        Button("Quit Cogi") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func preview(for text: String) -> String {
        let prefix = text.prefix(100)
        let singleLine = prefix
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let visibleText = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = visibleText.isEmpty ? "(Whitespace text)" : visibleText
        return text.dropFirst(100).isEmpty ? label : label + "…"
    }
}

#Preview {
    ContentView(clipboardMonitor: ClipboardMonitor())
}
