import SwiftUI

/// Re-reads and re-renders the focused document. Exposed through focused values for the View ▸ Reload menu.
struct ReloadAction {
    let run: @MainActor () -> Void
}

private struct ReloadDocumentKey: FocusedValueKey {
    typealias Value = ReloadAction
}

extension FocusedValues {
    var reloadDocument: ReloadAction? {
        get { self[ReloadDocumentKey.self] }
        set { self[ReloadDocumentKey.self] = newValue }
    }
}
