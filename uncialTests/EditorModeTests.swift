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

    /// The raw values are stored in the settings. Live Preview is stored as `inlinePreview`: until
    /// 2026-09-15 `livePreview` meant the split, a value `AppSettings` migrates.
    @Test func storedValuesAndShortcuts() {
        #expect(EditorMode.allCases.map(\.rawValue) == ["readOnly", "inlinePreview", "split", "rawEditor"])
        #expect(EditorMode.legacySplitRawValue == "livePreview")
        #expect(EditorMode.allCases.map(\.shortcut) == [.readOnly, .livePreview, .splitView, .rawEditor])
    }
}
