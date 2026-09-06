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
