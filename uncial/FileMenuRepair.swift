import AppKit

/// Keeps the File menu's document items as the app declares them, whatever SwiftUI does to the menu.
///
/// SwiftUI updates its menu bar items each time a menu opens, and when the system reads the menus by
/// itself. On macOS 27.2 that update shows `DocumentGroup(viewing:)`'s disabled stock New again next to
/// File ▸ New…, and, because the app replaces the `.saveItem` group, puts an item with no title (it reads
/// “NSMenuItem”), action or submenu where AppKit's Open Recent was. Neither can be declared away: no
/// command group placement holds Open… and Open Recent on 27.2, and earlier systems keep them in `.newItem`
/// with New. So the repair runs after every change to a menu, synchronously, inside SwiftUI's update: it
/// hides the stock New and gives the empty item a title and `RecentDocumentsMenu`. It changes items but
/// never adds, removes or moves one, since SwiftUI updates its items by index.
final class FileMenuRepair {
    static let openRecentTitle = "Open Recent"
    private let recentDocuments: RecentDocumentsMenu
    private var observers: [NSObjectProtocol] = []

    init(recentDocuments: RecentDocumentsMenu = RecentDocumentsMenu()) {
        self.recentDocuments = recentDocuments
    }

    /// Repairs the menu bar now and every menu after each change to it.
    func start() {
        guard observers.isEmpty else { return }
        NSApp.mainMenu?.items.compactMap(\.submenu).forEach(repair)
        // No queue: the repair runs on the posting thread, before the menu shows. Menus change on the main
        // thread only.
        observers = [NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
                MainActor.assumeIsolated {
                    if let menu = note.object as? NSMenu {
                        self?.repair(menu)
                    }
                }
            }
        }
    }

    /// In the menu with Open… (File): hides every stock New, and makes the item after Open… Open Recent when
    /// it can do nothing (no submenu, no action). Sets only what differs, so the notifications its own
    /// changes post find nothing left to do.
    func repair(_ menu: NSMenu) {
        let items = menu.items
        guard let open = items.firstIndex(where: { $0.action == #selector(NSDocumentController.openDocument(_:)) }) else { return }
        for item in items where item.action == #selector(NSDocumentController.newDocument(_:)) && !item.isHidden {
            item.isHidden = true
        }
        guard open + 1 < items.count else { return }
        let slot = items[open + 1]
        if slot.submenu == nil, !slot.isSeparatorItem, slot.action == nil || slot.action == #selector(NSMenu.submenuAction(_:)) {
            slot.submenu = recentDocuments.makeMenu()
        }
        if slot.submenu?.delegate === recentDocuments, slot.title != Self.openRecentTitle {
            slot.title = Self.openRecentTitle
        }
    }
}
