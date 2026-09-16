import AppKit

/// The sheets a manually saved document shows before unsaved edits could be lost: the standard
/// Save / Cancel / Don't Save question when a window closes or the app quits, and a Revert / Cancel
/// question before View ▸ Reload adopts the disk text.
enum UnsavedChangesAlert {
    enum Choice: Equatable {
        case save, discard, cancel
    }

    /// Buttons in AppKit's own order: Save (default) and Cancel on the right, Don't Save (⌘D) at the left.
    static func makeAlert(documentName: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to the document “\(documentName)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let discard = alert.addButton(withTitle: "Don't Save")
        discard.hasDestructiveAction = true
        discard.keyEquivalent = "d"
        discard.keyEquivalentModifierMask = .command
        return alert
    }

    static func makeRevertAlert(documentName: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Do you want to revert to the saved version of “\(documentName)”?"
        alert.informativeText = "Your unsaved changes will be lost."
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    static func choice(for response: NSApplication.ModalResponse) -> Choice {
        switch response {
        case .alertFirstButtonReturn: .save
        case .alertThirdButtonReturn: .discard
        default: .cancel
        }
    }

    /// Asks on a sheet over `window` and returns the choice.
    static func ask(documentName: String, in window: NSWindow) async -> Choice {
        await withCheckedContinuation { continuation in
            makeAlert(documentName: documentName).beginSheetModal(for: window) { response in
                continuation.resume(returning: choice(for: response))
            }
        }
    }

    /// Whether the user confirmed dropping the unsaved edits.
    static func confirmRevert(documentName: String, in window: NSWindow) async -> Bool {
        await withCheckedContinuation { continuation in
            makeRevertAlert(documentName: documentName).beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }
}
