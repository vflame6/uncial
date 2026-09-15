import Testing
@testable import Uncial

@Suite struct EditorModeTests {
    @Test func cyclesThroughAllModes() {
        #expect(EditorMode.readOnly.next == .livePreview)
        #expect(EditorMode.livePreview.next == .split)
        #expect(EditorMode.split.next == .rawEditor)
        #expect(EditorMode.rawEditor.next == .readOnly)
        #expect(EditorMode.allCases == [.readOnly, .livePreview, .split, .rawEditor])
    }

    @Test func paneVisibility() {
        #expect(EditorMode.readOnly.showsEditor == false && EditorMode.readOnly.showsPreview == true)
        #expect(EditorMode.livePreview.showsEditor == true && EditorMode.livePreview.showsPreview == false)
        #expect(EditorMode.split.showsEditor == true && EditorMode.split.showsPreview == true)
        #expect(EditorMode.rawEditor.showsEditor == true && EditorMode.rawEditor.showsPreview == false)
    }

    @Test func onlyLivePreviewRendersInline() {
        #expect(EditorMode.livePreview.presentation == .inline)
        #expect(EditorMode.allCases.filter { $0.presentation == .source } == [.readOnly, .split, .rawEditor])
    }

    @Test func storedValuesAndShortcuts() {
        #expect(EditorMode.livePreview.rawValue == "inlinePreview")
        #expect(EditorMode.split.rawValue == "split")
        #expect(EditorMode.legacySplitRawValue == "livePreview")
        #expect(EditorMode.allCases.map(\.shortcut.display) == ["⌥⌘1", "⌥⌘2", "⌥⌘3", "⌥⌘4"])
        #expect(EditorMode.split.title == "Split View" && EditorMode.livePreview.title == "Live Preview")
    }
}
