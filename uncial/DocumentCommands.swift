import AppKit
import SwiftUI

/// Re-reads and re-renders the focused document (View ▸ Reload).
struct ReloadAction {
    let run: @MainActor () -> Void
}

/// Writes the focused document now (File ▸ Save).
struct SaveAction {
    let run: @MainActor () -> Void
}

/// Drives the focused editor's find bar (Edit ▸ Find).
struct FindAction {
    let perform: @MainActor (NSTextFinder.Action) -> Void
}

private struct ReloadDocumentKey: FocusedValueKey {
    typealias Value = ReloadAction
}

private struct SaveDocumentKey: FocusedValueKey {
    typealias Value = SaveAction
}

private struct EditorModeKey: FocusedValueKey {
    typealias Value = Binding<EditorMode>
}

private struct FindInSourceKey: FocusedValueKey {
    typealias Value = FindAction
}

extension FocusedValues {
    var reloadDocument: ReloadAction? {
        get { self[ReloadDocumentKey.self] }
        set { self[ReloadDocumentKey.self] = newValue }
    }

    var saveDocument: SaveAction? {
        get { self[SaveDocumentKey.self] }
        set { self[SaveDocumentKey.self] = newValue }
    }

    var editorMode: Binding<EditorMode>? {
        get { self[EditorModeKey.self] }
        set { self[EditorModeKey.self] = newValue }
    }

    var findInSource: FindAction? {
        get { self[FindInSourceKey.self] }
        set { self[FindInSourceKey.self] = newValue }
    }
}
