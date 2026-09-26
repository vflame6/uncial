import AppKit
import Testing
@testable import Uncial

/// Opens real document windows in the test host, so the suite runs one test at a time and closes
/// what it opened.
@MainActor
@Suite(.serialized) struct DocumentWindowGuardTests {
    private func temporaryFile(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-guard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("doc.md")
        try Data(contents.utf8).write(to: file)
        return file
    }

    private func contents(of file: URL) throws -> String {
        String(decoding: try Data(contentsOf: file), as: UTF8.self)
    }

    /// Opens `file` through the document controller and waits for the guard to attach.
    private func open(_ file: URL) async throws -> (NSWindow, DocumentWindowGuard) {
        let (document, _) = try await NSDocumentController.shared.openDocument(withContentsOf: file, display: true)
        for _ in 0..<60 {
            if let window = document.windowControllers.first?.window,
               let guardian = DocumentWindowGuard.installed(on: window), guardian.model != nil {
                return (window, guardian)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("The window never got its guard")
        throw CancellationError()
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    /// A dismissed sheet stays attached while it animates out; a new one would queue behind it.
    private func waitForSheetToGo(on window: NSWindow) async throws {
        for _ in 0..<40 where window.attachedSheet != nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(window.attachedSheet == nil)
    }

    private func button(titled title: String, in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.title == title { return button }
        for subview in view.subviews {
            if let found = button(titled: title, in: subview) { return found }
        }
        return nil
    }

    private func click(_ title: String, onSheetOf window: NSWindow) throws {
        let found = button(titled: title, in: window.attachedSheet?.contentView)
        #expect(found != nil, "no \(title) button on the sheet")
        found?.performClick(nil)
    }

    @Test func mapsAlertButtonsToChoices() {
        #expect(UnsavedChangesAlert.choice(for: .alertFirstButtonReturn) == .save)
        #expect(UnsavedChangesAlert.choice(for: .alertSecondButtonReturn) == .cancel)
        #expect(UnsavedChangesAlert.choice(for: .alertThirdButtonReturn) == .discard)
        #expect(UnsavedChangesAlert.choice(for: .cancel) == .cancel)
        let alert = UnsavedChangesAlert.makeAlert(documentName: "notes.md")
        #expect(alert.buttons.map(\.title) == ["Save", "Cancel", "Don't Save"])
        #expect(alert.messageText.contains("notes.md"))
        let change = UnsavedChangesAlert.makeExternalChangeAlert(documentName: "notes.md")
        #expect(change.buttons.map(\.title) == ["Keep My Edits", "Reload"])
        #expect(change.messageText.contains("notes.md"))
    }

    @Test func asksWhenTheFileChangesUnderUnsavedEdits() async throws {
        let file = try temporaryFile("one")
        let (window, guardian) = try await open(file)
        let model = try #require(guardian.model)
        model.autosaves = false
        model.externalChangePolicy = .ask
        model.updateText("mine")
        try await settle()
        try Data("theirs".utf8).write(to: file)
        for _ in 0..<40 where window.attachedSheet == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(window.attachedSheet != nil)
        #expect(model.pendingExternalChange == "theirs")
        try click("Keep My Edits", onSheetOf: window)
        try await settle()
        #expect(model.text == "mine")
        #expect(model.needsSavePrompt == true)
        #expect(try contents(of: file) == "theirs")
        try await waitForSheetToGo(on: window)
        try Data("theirs again".utf8).write(to: file)
        for _ in 0..<40 where window.attachedSheet == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(window.attachedSheet != nil)
        try click("Reload", onSheetOf: window)
        try await settle()
        #expect(model.text == "theirs again")
        #expect(model.needsSavePrompt == false)
        try await waitForSheetToGo(on: window)
        window.performClose(nil)
        try await settle()
        #expect(window.isVisible == false)
    }

    @Test func closesACleanWindowWithoutAsking() async throws {
        let file = try temporaryFile("clean")
        let (window, _) = try await open(file)
        window.performClose(nil)
        try await settle()
        #expect(window.isVisible == false)
        #expect(window.attachedSheet == nil)
    }

    @Test func asksBeforeClosingUnsavedManualEditsAndCanDiscardThem() async throws {
        let file = try temporaryFile("one")
        let (window, guardian) = try await open(file)
        let model = try #require(guardian.model)
        model.autosaves = false
        model.updateText("two")
        try await settle()
        #expect(window.isDocumentEdited == true)
        window.performClose(nil)
        try await settle()
        #expect(window.isVisible == true)
        #expect(window.attachedSheet != nil)
        try click("Don't Save", onSheetOf: window)
        try await settle()
        #expect(window.isVisible == false)
        #expect(try contents(of: file) == "one")
    }

    @Test func saveButtonWritesThenCloses() async throws {
        let file = try temporaryFile("one")
        let (window, guardian) = try await open(file)
        let model = try #require(guardian.model)
        model.updateText("two")
        window.performClose(nil)
        try await settle()
        try click("Save", onSheetOf: window)
        try await settle()
        #expect(window.isVisible == false)
        #expect(try contents(of: file) == "two")
    }

    /// Another program wrote the file right before Save was clicked, before the watcher reported it:
    /// the window asks about the change instead of closing without writing.
    @Test func saveInTheCloseSheetAsksAboutAnUnreportedChange() async throws {
        let file = try temporaryFile("one")
        let (window, guardian) = try await open(file)
        let model = try #require(guardian.model)
        model.autosaves = false
        model.externalChangePolicy = .ask
        model.updateText("mine")
        try await settle()
        window.performClose(nil)
        try await settle()
        #expect(window.attachedSheet != nil)
        try Data("theirs".utf8).write(to: file)
        try click("Save", onSheetOf: window)
        try await settle()
        #expect(window.isVisible == true)
        #expect(try contents(of: file) == "theirs")
        #expect(window.attachedSheet != nil)
        try click("Keep My Edits", onSheetOf: window)
        try await settle()
        #expect(try contents(of: file) == "mine")
        #expect(window.isVisible == false)
    }

    /// With automatic saving, a write that fails at close or quit time keeps the window and asks.
    @Test func failedAutomaticSaveAsksBeforeClosingOrQuitting() async throws {
        let file = try temporaryFile("one")
        let directory = file.deletingLastPathComponent()
        let (window, guardian) = try await open(file)
        let model = try #require(guardian.model)
        model.autosaves = true
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        model.updateText("two")
        #expect(NSApp.delegate?.applicationShouldTerminate?(NSApp) == .terminateLater)
        try await settle()
        #expect(window.attachedSheet != nil)
        try click("Cancel", onSheetOf: window)
        try await waitForSheetToGo(on: window)
        window.performClose(nil)
        try await settle()
        #expect(window.isVisible == true)
        #expect(window.attachedSheet != nil)
        #expect(model.saveError != nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try click("Save", onSheetOf: window)
        try await settle()
        #expect(window.isVisible == false)
        #expect(try contents(of: file) == "two")
    }

    /// Renaming or moving the open file (as Finder, `mv` or a sync client does): the window's model
    /// follows it, so ⌘S writes the renamed file and does not bring back the old one.
    @Test func savesWhereTheFileWasMoved() async throws {
        let file = try temporaryFile("one")
        let (window, guardian) = try await open(file)
        let model = try #require(guardian.model)
        model.autosaves = false
        model.updateText("edited after rename")
        let renamed = file.deletingLastPathComponent().appendingPathComponent("renamed.md")
        try FileManager.default.moveItem(at: file, to: renamed)
        for _ in 0..<60 where model.fileURL?.lastPathComponent != "renamed.md" {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.fileURL?.lastPathComponent == "renamed.md")
        #expect(model.saveNow() == .written)
        #expect(try contents(of: renamed) == "edited after rename")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        window.performClose(nil)
        try await settle()
        #expect(window.isVisible == false)
    }

    @Test func cancelKeepsTheWindowAndTheEdits() async throws {
        let file = try temporaryFile("one")
        let (window, guardian) = try await open(file)
        let model = try #require(guardian.model)
        model.updateText("two")
        window.performClose(nil)
        try await settle()
        try click("Cancel", onSheetOf: window)
        try await settle()
        #expect(window.isVisible == true)
        #expect(window.attachedSheet == nil)
        #expect(model.text == "two")
        #expect(try contents(of: file) == "one")
        // Leave nothing open.
        try await waitForSheetToGo(on: window)
        window.performClose(nil)
        try await settle()
        try click("Don't Save", onSheetOf: window)
        try await settle()
        #expect(window.isVisible == false)
    }

    @Test func autosavingWindowsCloseQuietly() async throws {
        let file = try temporaryFile("one")
        let (window, guardian) = try await open(file)
        let model = try #require(guardian.model)
        model.autosaves = true
        model.updateText("two")
        #expect(window.isDocumentEdited == false)
        window.performClose(nil)
        try await settle()
        #expect(window.isVisible == false)
        #expect(window.attachedSheet == nil)
        #expect(try contents(of: file) == "two")
    }

    @Test func editedDotFollowsTheUnsavedState() async throws {
        let file = try temporaryFile("one")
        let (window, guardian) = try await open(file)
        let model = try #require(guardian.model)
        model.updateText("two")
        try await settle()
        #expect(window.isDocumentEdited == true)
        #expect(DocumentWindowGuard.needingReview.contains { $0 === guardian })
        model.saveNow()
        try await settle()
        #expect(window.isDocumentEdited == false)
        #expect(!DocumentWindowGuard.needingReview.contains { $0 === guardian })
        window.performClose(nil)
        try await settle()
        #expect(window.isVisible == false)
    }

    @Test func reloadAsksBeforeDroppingUnsavedEdits() async throws {
        let file = try temporaryFile("one")
        let (window, guardian) = try await open(file)
        let model = try #require(guardian.model)
        model.updateText("two")
        try Data("disk".utf8).write(to: file)
        let reload = Task { await guardian.reload() }
        try await settle()
        #expect(window.attachedSheet != nil)
        try click("Cancel", onSheetOf: window)
        await reload.value
        #expect(model.text == "two")
        try await waitForSheetToGo(on: window)
        let reloadAgain = Task { await guardian.reload() }
        try await settle()
        try click("Revert", onSheetOf: window)
        await reloadAgain.value
        #expect(model.text == "disk")
        window.performClose(nil)
        try await settle()
        #expect(window.isVisible == false)
    }

    @Test func quitReviewStopsAtCancelAndSavesOnRequest() async throws {
        let first = try temporaryFile("first")
        let second = try temporaryFile("second")
        let (window1, guard1) = try await open(first)
        let (window2, guard2) = try await open(second)
        try #require(guard1.model).updateText("first edited")
        try #require(guard2.model).updateText("second edited")
        let review = Task { await DocumentWindowGuard.review([guard1, guard2]) }
        try await settle()
        try click("Save", onSheetOf: window1)
        try await settle()
        #expect(try contents(of: first) == "first edited")
        try click("Cancel", onSheetOf: window2)
        #expect(await review.value == false)
        #expect(try contents(of: second) == "second")
        try await waitForSheetToGo(on: window2)
        #expect(DocumentWindowGuard.needingReview.map { $0 === guard2 } == [true])
        let reviewAgain = Task { await DocumentWindowGuard.review(DocumentWindowGuard.needingReview) }
        try await settle()
        #expect(window1.attachedSheet == nil)
        try click("Don't Save", onSheetOf: window2)
        #expect(await reviewAgain.value == true)
        #expect(try contents(of: second) == "second")
        // Don't Save keeps the edits in memory (a later Cancel could still stop the quit).
        window1.performClose(nil)
        window2.performClose(nil)
        try await settle()
        #expect(window1.isVisible == false)
        try click("Don't Save", onSheetOf: window2)
        try await settle()
        #expect(window2.isVisible == false)
    }

    /// A minimized window and the windows of a hidden app are not visible but still hold unsaved
    /// edits: quitting asks about them, back on screen.
    @Test func quitReviewIncludesMinimizedWindowsAndAHiddenApp() async throws {
        let file = try temporaryFile("one")
        let (window, guardian) = try await open(file)
        let model = try #require(guardian.model)
        model.autosaves = false
        model.updateText("two")
        try await settle()
        window.miniaturize(nil)
        for _ in 0..<40 where !window.isMiniaturized {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(window.isMiniaturized)
        #expect(DocumentWindowGuard.needingReview.contains { $0 === guardian })
        #expect(NSApp.delegate?.applicationShouldTerminate?(NSApp) == .terminateLater)
        try await settle()
        #expect(window.isMiniaturized == false)
        #expect(window.attachedSheet != nil)
        try click("Cancel", onSheetOf: window)
        try await waitForSheetToGo(on: window)

        NSApp.hide(nil)
        for _ in 0..<40 where !NSApp.isHidden {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(DocumentWindowGuard.needingReview.contains { $0 === guardian })
        let review = Task { await DocumentWindowGuard.review(DocumentWindowGuard.needingReview) }
        try await settle()
        #expect(NSApp.isHidden == false)
        #expect(window.attachedSheet != nil)
        try click("Don't Save", onSheetOf: window)
        #expect(await review.value == true)
        #expect(try contents(of: file) == "one")

        // Leave nothing open, hidden or minimized.
        if NSApp.isHidden { NSApp.unhide(nil) }
        if window.isMiniaturized { window.deminiaturize(nil) }
        try await waitForSheetToGo(on: window)
        window.performClose(nil)
        try await settle()
        if window.attachedSheet != nil { try click("Don't Save", onSheetOf: window) }
        try await settle()
        #expect(window.isVisible == false)
    }

    @Test func quitAsksThroughTheAppDelegate() async throws {
        let file = try temporaryFile("one")
        let (window, guardian) = try await open(file)
        #expect(NSApp.delegate?.applicationShouldTerminate?(NSApp) == .terminateNow)
        try #require(guardian.model).updateText("two")
        #expect(NSApp.delegate?.applicationShouldTerminate?(NSApp) == .terminateLater)
        try await settle()
        #expect(window.attachedSheet != nil)
        try click("Cancel", onSheetOf: window)
        try await waitForSheetToGo(on: window)
        #expect(window.isVisible == true)
        window.performClose(nil)
        try await settle()
        try click("Don't Save", onSheetOf: window)
        try await settle()
        #expect(window.isVisible == false)
    }
}
