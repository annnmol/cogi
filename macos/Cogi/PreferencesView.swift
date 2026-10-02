import AppKit
import SwiftUI

@MainActor
enum PreferencesContent {
    static func makeViewController() -> NSTabViewController {
        let controller = NSTabViewController()
        controller.tabStyle = .toolbar

        // Match Maccy's native toolbar pane labels and symbols without adding
        // its settings dependencies. See Resources/Maccy-LICENSE.txt.
        let panes = [
            ("General", "gearshape"),
            ("Storage", "externaldrive"),
            ("Appearance", "paintpalette"),
            ("Pins", "pincircle"),
            ("Ignore", "nosign"),
            ("Advanced", "gearshape.2")
        ]
        for (title, symbol) in panes {
            let content = NSHostingController(rootView: Text("\(title) preferences test.")
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity))
            content.preferredContentSize = NSSize(width: 560, height: 260)
            let item = NSTabViewItem(viewController: content)
            item.identifier = title
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            controller.addTabViewItem(item)
        }
        controller.selectedTabViewItemIndex = 0
        return controller
    }
}
