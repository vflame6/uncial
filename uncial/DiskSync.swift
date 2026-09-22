/// Decides what to do when the file changes on disk under an open editor.
nonisolated enum DiskSync {
    enum Action: Equatable {
        /// Nothing to do: the change is our own write.
        case ignore
        /// Replace the editor text with the disk text.
        case adopt
        /// Keep the editor text; the pending save will overwrite the disk.
        case keepLocal
    }

    /// - Parameters:
    ///   - disk: the file's current contents
    ///   - text: the editor's current text
    ///   - diskText: what the model last loaded from or wrote to the file
    static func decide(disk: String, text: String, diskText: String) -> Action {
        if disk == diskText { return .ignore }
        if text == diskText || text == disk { return .adopt }
        return .keepLocal
    }
}

/// What happens when the file changes on disk while the window holds unsaved edits
/// (`AppSettings.externalChangePolicy`): ask on a sheet, keep the edits (the file's new contents are
/// replaced at the next save, right away with automatic saving), or reload the file and drop them.
/// Without unsaved edits the window always follows the file.
nonisolated enum ExternalChangePolicy: String, CaseIterable, Identifiable {
    case ask, keepLocal, reload

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask"
        case .keepLocal: "Keep my edits"
        case .reload: "Reload the file"
        }
    }
}

/// The answer to the Ask policy's question.
nonisolated enum ExternalChangeChoice: Equatable {
    case keepLocal, reload
}
