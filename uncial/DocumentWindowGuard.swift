import AppKit
import ObjectiveC
import SwiftUI

/// Stands between a document window and the unsaved edits of a manually saved document: shows the
/// edited dot in the close button, asks before the window closes or the document reverts, asks what
/// to do when another program changes the file, and lists the windows the app must ask about before
/// it quits. It also puts the window where its document was last time (`DocumentWindowFrames`).
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
    /// Where document windows were. The unit tests' host keeps them in memory, out of the user's defaults.
    static var frames = DocumentWindowFrames(defaults: AppDelegate.isTestHost(ProcessInfo.processInfo.environment) ? nil : .standard)

    /// The window's guard, created on first use, now watching `model`.
    @discardableResult
    static func install(on window: NSWindow, model: DocumentViewModel) -> DocumentWindowGuard {
        let guardian: DocumentWindowGuard
        if let existing = installed(on: window) {
            existing.model = model
            guardian = existing
        } else {
            guardian = DocumentWindowGuard(window: window, model: model)
            objc_setAssociatedObject(window, associationKey, guardian, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        model.externalChangeResolver = { [weak guardian] _ in await guardian?.askExternalChange() ?? .keepLocal }
        return guardian
    }

    static func installed(on window: NSWindow) -> DocumentWindowGuard? {
        objc_getAssociatedObject(window, associationKey) as? DocumentWindowGuard
    }

    /// Guards of the open document windows (on screen, minimized, or hidden with the app) whose
    /// document has unsaved edits nothing will write on its own, front to back. Closed document
    /// windows stay alive (SwiftUI keeps them) and would come back with `makeKeyAndOrderFront`, but
    /// their window controller no longer has a document, so they are left out.
    static var needingReview: [DocumentWindowGuard] {
        open.filter { $0.model?.needsSavePrompt == true }
    }

    /// Before the quit review: every open window's pending automatic save runs now, so a write that
    /// fails or a change on disk that needs an answer is asked about while its window is still here.
    static func flushAutomaticSaves() {
        open.forEach { $0.flushAutomaticSave() }
    }

    private static var open: [DocumentWindowGuard] {
        NSApp.orderedWindows.filter { $0.windowController?.document != nil }.compactMap { installed(on: $0) }
    }

    /// Asks about every window in turn, front to back, before the app quits, bringing a hidden app
    /// and a minimized window back on screen first. False as soon as one answer is Cancel (or a
    /// save fails); true when every document was saved or given up.
    static func review(_ guards: [DocumentWindowGuard]) async -> Bool {
        for guardian in guards {
            if NSApp.isHidden { NSApp.unhide(nil) }
            if guardian.window?.isMiniaturized == true { guardian.window?.deminiaturize(nil) }
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
        place(window)
    }

    /// The window is going: its place is kept, its model saves what saves on its own and stops (SwiftUI
    /// keeps the window alive, STAB-5). SwiftUI's controller, the delegate before us, hears about it too.
    func windowWillClose(_ notification: Notification) {
        rememberFrame()
        model?.saveIfAutomatic()
        model?.close()
        next?.windowWillClose?(notification)
    }

    // MARK: - The window's place

    /// Puts a window that has not shown yet (the guard arrives before it does, probed 2026-11-20) where
    /// its document's window was, exactly; or, for a document without a place of its own, where the last
    /// document window was, and then next to another document's window when that is the very spot, as
    /// the last window's often is.
    private func place(_ window: NSWindow) {
        // Asked before the frame is set: setting it is a move, which is remembered as the document's place.
        let own = Self.frames.ownFrame(for: model?.fileURL)
        guard !window.isVisible, let frame = own ?? Self.frames.frame(for: nil) else { return }
        window.setFrame(from: frame)
        guard own == nil else { return }
        let others = NSApp.windows.filter { $0 !== window && $0.isVisible && $0.windowController?.document != nil }
        for _ in 0..<others.count {
            guard let covered = others.first(where: { abs($0.frame.minX - window.frame.minX) < 4 && abs($0.frame.maxY - window.frame.maxY) < 4 }) else { break }
            // To the covered window's corner, which tells where the next window goes, then there.
            let next = window.cascadeTopLeft(from: NSPoint(x: covered.frame.minX, y: covered.frame.maxY))
            _ = window.cascadeTopLeft(from: next)
        }
    }

    /// Keeps the window's place for the next time its document opens (a tab in the background too:
    /// it has its window's frame). Not once the window has closed, and not in full screen, whose frame
    /// is the screen's.
    private func rememberFrame() {
        guard let window, let model, model.isOpen, !window.styleMask.contains(.fullScreen) else { return }
        Self.frames.remember(window.frameDescriptor, for: model.fileURL)
    }

    func windowDidMove(_ notification: Notification) {
        rememberFrame()
        next?.windowDidMove?(notification)
    }

    /// The size the window is given at once (zoom, a script); a resize by hand is kept when it ends.
    func windowDidResize(_ notification: Notification) {
        if window?.inLiveResize != true { rememberFrame() }
        next?.windowDidResize?(notification)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        rememberFrame()
        next?.windowDidEndLiveResize?(notification)
    }

    /// Mirrors `DocumentViewModel.needsSavePrompt` into the close button's dot and the title's "Edited".
    func setEdited(_ edited: Bool) {
        guard let window, window.isDocumentEdited != edited else { return }
        window.isDocumentEdited = edited
    }

    /// The Ask policy's question, on a sheet, when another program changed the file under unsaved
    /// edits. With a sheet already up, or no window on screen, the edits stay and nothing is written
    /// until the user acts.
    func askExternalChange() async -> ExternalChangeChoice {
        guard let model, let window, window.isVisible, window.attachedSheet == nil else { return .keepLocal }
        return await UnsavedChangesAlert.askExternalChange(documentName: model.title, in: window)
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
    /// (the edits are on disk) or discarded. A window that is already showing a sheet counts as
    /// Cancel: a second sheet would queue behind the first, and a queued sheet never answers once the
    /// first one closes the window.
    private func resolveUnsavedChanges() async -> Bool {
        guard let model, let window, model.needsSavePrompt else { return true }
        guard window.attachedSheet == nil else { return false }
        switch await UnsavedChangesAlert.ask(documentName: model.title, in: window) {
        case .save:
            return await save(model, in: window)
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    /// Save for a window that is about to go: true once the edits are on disk (or the Reload policy
    /// replaced them). A change on disk the watcher has not reported yet is asked about on this
    /// window first; a failed write keeps the window, its error in the editor.
    private func save(_ model: DocumentViewModel, in window: NSWindow) async -> Bool {
        switch model.saveBeforeClosing() {
        case .written, .unchanged, .adopted:
            return true
        case .failed:
            return false
        case .needsDecision:
            guard await sheetIsGone(from: window) else { return false }
            let choice = await UnsavedChangesAlert.askExternalChange(documentName: model.title, in: window)
            model.resolveExternalChange(choice)
            if choice == .reload { return true }
            return await save(model, in: window)
        }
    }

    /// A dismissed sheet stays attached while it animates out; the next one waits for it.
    private func sheetIsGone(from window: NSWindow) async -> Bool {
        for _ in 0..<40 where window.attachedSheet != nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return window.attachedSheet == nil
    }

    /// Automatic saving writes what is pending now, while the window can still report a failed
    /// write or ask about a change on disk; either one makes `needsSavePrompt` true.
    private func flushAutomaticSave() {
        guard let model, model.autosaves, model.hasUnsavedChanges, model.pendingExternalChange == nil else { return }
        _ = model.saveBeforeClosing()
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        flushAutomaticSave()
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
