import Testing
@testable import Uncial

@MainActor
@Suite struct AppShortcutTests {
    @Test func displaysAreUniqueAndNonEmpty() {
        let displays = AppShortcut.allCases.map(\.display)
        #expect(Set(displays).count == displays.count)
        #expect(displays.allSatisfy { !$0.isEmpty })
    }

    @Test func formatsModifiersInMenuOrder() {
        #expect(AppShortcut.toggleEditorMode.display == "⇧⌘E")
        #expect(AppShortcut.livePreview.display == "⌥⌘2")
        #expect(AppShortcut.reload.display == "⌘R")
    }

    /// Find, zoom and Settings keep the keys every Mac app gives them.
    @Test func standardCommandsKeepTheSystemsShortcuts() {
        #expect(AppShortcut.find.display == "⌘F")
        #expect(AppShortcut.findAndReplace.display == "⌥⌘F")
        #expect(AppShortcut.findNext.display == "⌘G")
        #expect(AppShortcut.findPrevious.display == "⇧⌘G")
        #expect(AppShortcut.useSelectionForFind.display == "⌘E")
        #expect(AppShortcut.zoomIn.display == "⌘=" && AppShortcut.zoomOut.display == "⌘-" && AppShortcut.actualSize.display == "⌘0")
        #expect(AppShortcut.settings.display == "⌘,")
    }

    /// The Shortcuts tab lists the table by menu, in menu order.
    @Test func sectionsKeepMenuOrder() {
        #expect(AppShortcut.sections == ["File", "View", "Edit", "Uncial"])
        #expect(AppShortcut.shortcuts(in: "File") == [.newDocument, .open, .save, .export, .close, .closeAll])
        #expect(AppShortcut.shortcuts(in: "View") == [.readOnly, .livePreview, .splitView, .rawEditor, .toggleEditorMode, .reload, .zoomIn, .zoomOut, .actualSize])
        #expect(AppShortcut.shortcuts(in: "Edit") == [.find, .findAndReplace, .findNext, .findPrevious, .useSelectionForFind])
    }
}
