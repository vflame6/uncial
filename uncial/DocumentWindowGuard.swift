import AppKit
import ObjectiveC
import SwiftUI

/// Stands between a document window and the unsaved edits of a manually saved document: shows the
/// edited dot in the close button, asks before the window closes or the document reverts, and lists
/// the windows the app must ask about before it quits.
///
/// Installed as the window's delegate in front of SwiftUI's own window controller, which was the
/// delegate before (probed 2026-09-16: `AppKitWindowController`, and it answers `windowShouldClose`);
/// every other delegate message is forwarded to it. NSDocument's change count stays untouched:
/// SwiftUI's document autosaves in place, so a change registered there would make it write its
/// read-only copy of the text.
final class DocumentWindowGuard: NSObject, NSWindowDelegate {
    private(set) weak var window: NSWindow?
    private(set) weak var model: DocumentViewModel?
    /// The delegate before us; AppKit reads `responds(to:)` once when the delegate is set.
    nonisolated(unsafe) private weak var next: NSWindowDelegate?
    private static let associationKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    /// The window's guard, created on first use, now watching `model`.
    @discardableResult
    static func install(on window: NSWindow, model: DocumentViewModel) -> DocumentWindowGuard {
        if let existing = installed(on: window) {
            existing.model = model
            return existing
        }
        let guardian = DocumentWindowGuard(window: window, model: model)
        objc_setAssociatedObject(window, associationKey, guardian, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return guardian
    }

    static func installed(on window: NSWindow) -> DocumentWindowGuard? {
        objc_getAssociatedObject(window, associationKey) as? DocumentWindowGuard
    }

    /// Guards of the windows on screen whose document has unsaved edits nothing will write on its
    /// own, front to back. Closed document windows stay alive (SwiftUI keeps them) and would come
    /// back with `makeKeyAndOrderFront`, hence the visibility check.
    static var needingReview: [DocumentWindowGuard] {
        NSApp.orderedWindows.filter(\.isVisible).compactMap(installed(on:)).filter { $0.model?.needsSavePrompt == true }
    }

    /// Asks about every window in turn, front to back, before the app quits. False as soon as one
    /// answer is Cancel (or a save fails); true when every document was saved or given up.
    static func review(_ guards: [DocumentWindowGuard]) async -> Bool {
        for guardian in guards {
            guardian.window?.makeKeyAndOrderFront(nil)
            guard await guardian.resolveUnsavedChanges() else { return false }
        }
        return true
    }

    private init(window: NSWindow, model: DocumentViewModel) {
        self.window = window
        self.model = model
        next = window.delegate
        super.init()
        window.delegate = self
    }

    /// Mirrors `DocumentViewModel.needsSavePrompt` into the close button's dot and the title's "Edited".
    func setEdited(_ edited: Bool) {
        guard let window, window.isDocumentEdited != edited else { return }
        window.isDocumentEdited = edited
    }

    /// View ▸ Reload: confirms first when unsaved edits would be dropped.
    func reload() async {
        guard let model else { return }
        if model.needsSavePrompt, let window {
            guard window.attachedSheet == nil,
                  await UnsavedChangesAlert.confirmRevert(documentName: model.title, in: window) else { return }
        }
        model.reload()
    }

    /// Presents the Save / Cancel / Don't Save sheet and returns whether the window may go: saved
    /// (and the write succeeded) or discarded. A window that is already showing a sheet counts as
    /// Cancel: a second sheet would queue behind the first, and a queued sheet never answers once the
    /// first one closes the window.
    private func resolveUnsavedChanges() async -> Bool {
        guard let model, let window, model.needsSavePrompt else { return true }
        guard window.attachedSheet == nil else { return false }
        switch await UnsavedChangesAlert.ask(documentName: model.title, in: window) {
        case .save:
            model.saveNow()
            return model.saveError == nil
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let model, model.needsSavePrompt else {
            return next?.windowShouldClose?(sender) ?? true
        }
        Task { @MainActor in
            guard await resolveUnsavedChanges() else { return }
            // What performClose would have done: the controller closes the document itself when it
            // answers false.
            if next?.windowShouldClose?(sender) ?? true {
                sender.close()
            }
        }
        return false
    }

    override nonisolated func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || next?.responds(to: aSelector) == true
    }

    override nonisolated func forwardingTarget(for aSelector: Selector!) -> Any? {
        next
    }
}

/// Reaches the document's guard from SwiftUI (View ▸ Reload needs it for the confirmation sheet).
final class DocumentWindowHandle {
    weak var guardian: DocumentWindowGuard?
}

/// Zero-size view that finds the document's window, installs the guard on it and keeps the window's
/// edited dot in step with the model.
struct DocumentWindowBridge: NSViewRepresentable {
    let model: DocumentViewModel
    let isEdited: Bool
    let handle: DocumentWindowHandle

    func makeNSView(context: Context) -> BridgeView {
        BridgeView()
    }

    func updateNSView(_ view: BridgeView, context: Context) {
        view.model = model
        view.isEdited = isEdited
        view.handle = handle
        view.apply()
    }

    final class BridgeView: NSView {
        var model: DocumentViewModel?
        var isEdited = false
        var handle: DocumentWindowHandle?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window, let model else { return }
            let guardian = DocumentWindowGuard.install(on: window, model: model)
            guardian.setEdited(isEdited)
            handle?.guardian = guardian
        }
    }
}
