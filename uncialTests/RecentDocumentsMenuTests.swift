import AppKit
import Testing
@testable import Uncial

@MainActor
@Suite struct RecentDocumentsMenuTests {
    private let folder = TemporaryDirectory()

    /// The submenu `recent` makes, filled as on opening. Its delegate and its items' target are weak: keep
    /// `recent` while using the menu.
    private func filled(_ recent: RecentDocumentsMenu) -> NSMenu {
        let menu = recent.makeMenu()
        menu.delegate?.menuNeedsUpdate?(menu)
        return menu
    }

    /// Two notes called README.md get their folders' names after theirs, as in AppKit's Open Recent.
    @Test func namesTwoDocumentsShareGetTheirFolders() {
        let urls = ["/a/notes/README.md", "/b/uncial/README.md", "/b/uncial/todo.md"].map { URL(fileURLWithPath: $0) }
        #expect(RecentDocumentsMenu.titles(for: urls) { $0.lastPathComponent } == ["README.md — notes", "README.md — uncial", "todo.md"])
    }

    /// The recent documents in the controller's order, then Clear Menu; choosing one opens it.
    @Test func listsTheRecentDocumentsAndOpensTheOneChosen() throws {
        let first = try folder.file("first.md")
        let second = try folder.file("second.md")
        var opened: [URL] = []
        var cleared = 0
        let recent = RecentDocumentsMenu(urls: { [first, second] }, open: { opened.append($0) }, clear: { cleared += 1 })
        let menu = filled(recent)
        let names = [first, second].map { FileManager.default.displayName(atPath: $0.path) }
        #expect(menu.items.map(\.title) == names + ["", "Clear Menu"])
        #expect(menu.items.prefix(2).allSatisfy { $0.image?.size == NSSize(width: 16, height: 16) })
        withExtendedLifetime(recent) {
            menu.performActionForItem(at: 1)
            menu.performActionForItem(at: 3)
        }
        #expect(opened == [second])
        #expect(cleared == 1)
    }

    /// With nothing recent, a disabled Clear Menu is all there is.
    @Test func anEmptyListLeavesClearMenuDisabled() {
        let menu = filled(RecentDocumentsMenu(urls: { [] }, open: { _ in }, clear: {}))
        #expect(menu.items.map(\.title) == ["Clear Menu"])
        #expect(menu.items.first?.isEnabled == false)
    }
}
