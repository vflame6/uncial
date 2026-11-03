import AppKit
import Testing
@testable import Uncial

/// The menus SwiftUI builds from `UncialApp`'s commands, as the test host (the app itself) shows them.
@MainActor
@Suite struct AppMenuTests {
    private func fileMenu() throws -> NSMenu {
        try #require(NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu)
    }

    /// What opening `menu` does: its delegate (SwiftUI, for the menu bar's menus) updates the items, then
    /// AppKit validates them.
    private func open(_ menu: NSMenu) {
        menu.delegate?.menuNeedsUpdate?(menu)
        menu.delegate?.menuWillOpen?(menu)
        menu.update()
        menu.delegate?.menuDidClose?(menu)
    }

    /// The File menu reads New…, Open…, Open Recent ▸ however often SwiftUI updates it, which it does each
    /// time the menu opens. On macOS 27.2 the first update showed `DocumentGroup(viewing:)`'s disabled stock
    /// New again (the app hid it once, at launch) and swapped Open Recent for an untitled “NSMenuItem”.
    @Test func fileMenuKeepsItsDocumentItemsThroughUpdates() throws {
        let file = try fileMenu()
        open(file)
        open(file)
        let visible = file.items.filter { !$0.isHidden }
        #expect(visible.map(\.title) == ["New…", "Open…", "Open Recent", "", "Close", "Close All", "", "Save", "", "Export…"])
        let recent = try #require(visible.first { $0.title == "Open Recent" }?.submenu)
        open(recent)
        #expect(recent.items.last?.title == "Clear Menu")
    }

    /// File ▸ Export… owns ⌘P and ends the menu: SwiftUI's Print… and Page Setup… are gone, and no
    /// separator dangles after Export….
    @Test func fileMenuEndsWithExportOnCommandP() throws {
        let file = try fileMenu()
        let last = try #require(file.items.last { !$0.isHidden })
        #expect(last.title == "Export…", "the File menu ends with “\(last.isSeparatorItem ? "a separator" : last.title)”")
        #expect(last.keyEquivalent == "p" && last.keyEquivalentModifierMask == .command)
        #expect(!file.items.contains { $0.title.hasPrefix("Print") || $0.title.hasPrefix("Page Setup") })
        let items = NSApp.mainMenu?.items.flatMap { $0.submenu?.items ?? [] } ?? []
        #expect(items.filter { $0.keyEquivalent == "p" && $0.keyEquivalentModifierMask == .command }.count == 1)
    }
}
