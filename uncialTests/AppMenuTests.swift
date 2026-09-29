import AppKit
import Testing
@testable import Uncial

/// The menus SwiftUI builds from `UncialApp`'s commands, as the test host (the app itself) shows them.
@MainActor
@Suite struct AppMenuTests {
    /// File ▸ Export… owns ⌘P and ends the menu: SwiftUI's Print… and Page Setup… are gone, and no
    /// separator dangles after Export….
    @Test func fileMenuEndsWithExportOnCommandP() throws {
        let file = try #require(NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu)
        let last = try #require(file.items.last { !$0.isHidden })
        #expect(last.title == "Export…", "the File menu ends with “\(last.isSeparatorItem ? "a separator" : last.title)”")
        #expect(last.keyEquivalent == "p" && last.keyEquivalentModifierMask == .command)
        #expect(!file.items.contains { $0.title.hasPrefix("Print") || $0.title.hasPrefix("Page Setup") })
        let items = NSApp.mainMenu?.items.flatMap { $0.submenu?.items ?? [] } ?? []
        #expect(items.filter { $0.keyEquivalent == "p" && $0.keyEquivalentModifierMask == .command }.count == 1)
    }
}
