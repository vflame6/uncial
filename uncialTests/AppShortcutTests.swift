import Testing
@testable import Uncial

@Suite struct AppShortcutTests {
    @Test func displaysAreUniqueAndNonEmpty() {
        let displays = AppShortcut.allCases.map(\.display)
        #expect(Set(displays).count == displays.count)
        #expect(displays.allSatisfy { !$0.isEmpty })
    }

    @Test func formatsModifiersInMenuOrder() {
        #expect(AppShortcut.toggleEditorMode.display == "⇧⌘E")
        #expect(AppShortcut.livePreview.display == "⌥⌘2")
        #expect(AppShortcut.settings.display == "⌘,")
        #expect(AppShortcut.reload.display == "⌘R")
    }

    @Test func sectionsKeepDeclarationOrder() {
        #expect(AppShortcut.sections == ["File", "View", "Edit", "Uncial"])
        #expect(AppShortcut.shortcuts(in: "View").first == .readOnly)
    }
}
