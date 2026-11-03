import AppKit

/// File ▸ Open Recent where SwiftUI left none that works (see `FileMenuRepair`), filled each time it
/// opens: the document controller's recent documents with their icons and, after a name two of them
/// share, the folder's name, then Clear Menu, as AppKit's own submenu lists them.
final class RecentDocumentsMenu: NSObject, NSMenuDelegate {
    private let urls: () -> [URL]
    private let open: (URL) -> Void
    private let clear: () -> Void

    /// The defaults reach the shared document controller only when called: `NSDocumentController.shared`
    /// asked for before SwiftUI installs its own controller would be a plain one, and SwiftUI's launch then
    /// crashes.
    init(urls: @escaping () -> [URL] = { NSDocumentController.shared.recentDocumentURLs },
         open: @escaping (URL) -> Void = { RecentDocumentsMenu.openDocument($0) },
         clear: @escaping () -> Void = { NSDocumentController.shared.clearRecentDocuments(nil) }) {
        self.urls = urls
        self.open = open
        self.clear = clear
    }

    /// An empty submenu that this object fills when it opens.
    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: FileMenuRepair.openRecentTitle)
        menu.autoenablesItems = false
        menu.delegate = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let urls = urls()
        menu.removeAllItems()
        for (url, title) in zip(urls, Self.titles(for: urls)) {
            let item = NSMenuItem(title: title, action: #selector(openItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            item.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(item)
        }
        if !urls.isEmpty {
            menu.addItem(.separator())
        }
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearItems(_:)), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !urls.isEmpty
        menu.addItem(clear)
    }

    /// Nothing here has a shortcut; without this answer AppKit fills the menu to look for one.
    func menuHasKeyEquivalent(_ menu: NSMenu, for event: NSEvent, target: AutoreleasingUnsafeMutablePointer<AnyObject?>,
                              action: UnsafeMutablePointer<Selector?>) -> Bool {
        false
    }

    /// Each document's display name (extension shown as Finder shows it), followed by “ — ” and its
    /// folder's name when another document has the same one.
    nonisolated static func titles(for urls: [URL], displayName: (URL) -> String = { FileManager.default.displayName(atPath: $0.path) }) -> [String] {
        let names = urls.map(displayName)
        let counts = Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
        return zip(urls, names).map { url, name in
            counts[name, default: 0] > 1 ? "\(name) — \(displayName(url.deletingLastPathComponent()))" : name
        }
    }

    static func openDocument(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func openItem(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            open(url)
        }
    }

    @objc private func clearItems(_ sender: NSMenuItem) {
        clear()
    }
}
