import AppKit
import Testing
@testable import Uncial

/// The repair on menus built here in the shapes SwiftUI leaves the File menu in.
@MainActor
@Suite struct FileMenuRepairTests {
    private static let openDocument = #selector(NSDocumentController.openDocument(_:))

    private static func item(_ title: String, _ action: Selector? = nil, submenu: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if submenu {
            item.submenu = NSMenu(title: title)
        }
        return item
    }

    private func menu(_ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: "File")
        items.forEach(menu.addItem)
        return menu
    }

    /// What SwiftUI's update leaves on macOS 27.2: the stock New shown again and, after Open…, an item with
    /// no title, action or submenu. The stock New is hidden and the empty item becomes Open Recent, in
    /// place: nothing is added, removed or moved, since SwiftUI goes on updating its items by index.
    @Test func hidesTheStockNewAndMakesTheEmptyItemOpenRecent() throws {
        let new = Self.item("New", #selector(NSDocumentController.newDocument(_:)))
        let empty = NSMenuItem()
        let file = menu([Self.item("New…"), new, Self.item("Open…", Self.openDocument), empty, .separator(), Self.item("Close")])
        let before = file.items
        let repair = FileMenuRepair()
        repair.repair(file)
        #expect(new.isHidden)
        #expect(empty.title == "Open Recent")
        let submenu = try #require(empty.submenu)
        #expect(file.items == before)
        repair.repair(file)
        #expect(empty.submenu === submenu, "a second pass replaced the submenu")
    }

    enum Follower: CaseIterable {
        case workingOpenRecent, separator, command
    }

    /// Where Open Recent works (AppKit's own item, earlier systems), or something else follows Open…, the
    /// item stays as it is.
    @Test(arguments: Follower.allCases)
    func leavesAnItemThatWorksAlone(_ follower: Follower) {
        let next = switch follower {
        case .workingOpenRecent: Self.item("Open Recent", submenu: true)
        case .separator: NSMenuItem.separator()
        case .command: Self.item("Close", #selector(NSWindow.performClose(_:)))
        }
        let title = next.title
        let submenu = next.submenu
        FileMenuRepair().repair(menu([Self.item("Open…", Self.openDocument), next]))
        #expect(next.title == title)
        #expect(next.submenu === submenu)
    }
}
