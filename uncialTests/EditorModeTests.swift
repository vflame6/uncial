import Testing
@testable import Uncial

@Suite struct EditorModeTests {
    @Test func cyclesThroughAllModes() {
        #expect(EditorMode.readOnly.next == .livePreview)
        #expect(EditorMode.livePreview.next == .rawEditor)
        #expect(EditorMode.rawEditor.next == .readOnly)
    }

    @Test func paneVisibility() {
        #expect(EditorMode.readOnly.showsEditor == false && EditorMode.readOnly.showsPreview == true)
        #expect(EditorMode.livePreview.showsEditor == true && EditorMode.livePreview.showsPreview == true)
        #expect(EditorMode.rawEditor.showsEditor == true && EditorMode.rawEditor.showsPreview == false)
    }

    @Test func shortcutsAreDistinct() {
        #expect(Set(EditorMode.allCases.map(\.shortcut.display)).count == 3)
        #expect(EditorMode.readOnly.shortcut.display == "⌥⌘1")
    }
}
