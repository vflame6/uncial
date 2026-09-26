import Foundation
import Testing
import UncialCore
@testable import Uncial

@MainActor
@Suite struct DocumentViewModelTests {
    private func temporaryFile(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("doc.md")
        try Data(contents.utf8).write(to: file)
        return file
    }

    private func contents(of file: URL) throws -> String {
        String(decoding: try Data(contentsOf: file), as: UTF8.self)
    }

    /// The attachment search reaches the renderer and a change re-renders.
    @Test func attachmentSearchReRenders() async throws {
        let file = try temporaryFile("![a](a.gif)")
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        try Data([0x47, 0x49, 0x46]).write(to: directory.appendingPathComponent("attachments/a.gif"))
        let model = DocumentViewModel(fileURL: file, initialText: "![a](a.gif)", renderDelay: .milliseconds(20), saveDelay: .seconds(5))
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.body.contains("<img src=\"a.gif\""))
        model.attachmentSearch = AttachmentSearch()
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.body.contains("<img src=\"data:image/gif;base64,R0lG\""))
    }

    @Test func rendersInitialTextAndEdits() async throws {
        let file = try temporaryFile("# Hi")
        let model = DocumentViewModel(fileURL: file, initialText: "# Hi", renderDelay: .milliseconds(20), saveDelay: .seconds(5))
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.body.contains("<h1 id=\"hi\" data-line=\"1\" data-sourcepos=\"1:1-1:4\">Hi</h1>"))
        model.updateText("# Yo")
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.body.contains("<h1 id=\"yo\" data-line=\"1\" data-sourcepos=\"1:1-1:4\">Yo</h1>"))
        #expect(model.hasUnsavedChanges == true)
    }

    @Test func keepsStatisticsCurrent() async throws {
        let file = try temporaryFile("# Hi")
        let model = DocumentViewModel(fileURL: file, initialText: "# Hi", renderDelay: .milliseconds(20), saveDelay: .seconds(5))
        #expect(model.statistics == DocumentStatistics(lines: 1, words: 1, characters: 4))
        model.updateText("# Hi there\nmore")
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.statistics == DocumentStatistics(lines: 2, words: 3, characters: 15))
    }

    @Test func typingIsWrittenAfterThePause() async throws {
        let file = try temporaryFile("a")
        let model = DocumentViewModel(fileURL: file, initialText: "a", saveDelay: .milliseconds(50))
        model.autosaves = true
        model.updateText("ab")
        model.updateText("abc")
        #expect(try contents(of: file) == "a")
        try await Task.sleep(for: .milliseconds(400))
        #expect(try contents(of: file) == "abc")
        #expect(model.hasUnsavedChanges == false)
        #expect(model.saveError == nil)
    }

    /// A save changes the text, not the file around it: Finder tags, other extended attributes, the
    /// permissions and the creation date stay (an atomic write renamed a new file over the old one).
    @Test func saveKeepsTheFilesMetadata() throws {
        let file = try temporaryFile("old")
        let created = Date(timeIntervalSince1970: 1_577_836_800)
        var values = URLResourceValues()
        values.creationDate = created
        var url = file
        try url.setResourceValues(values)
        try (file as NSURL).setResourceValue(["Red", "Work"], forKey: .tagNamesKey)
        let marker = Array("kept".utf8)
        #expect(setxattr(file.path, "com.example.uncial", marker, marker.count, 0, 0) == 0)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)

        let model = DocumentViewModel(fileURL: file, initialText: "old", saveDelay: .seconds(5))
        model.updateText("new")
        #expect(model.saveNow() == .written)

        #expect(try contents(of: file) == "new")
        let after = try URL(fileURLWithPath: file.path).resourceValues(forKeys: [.tagNamesKey, .creationDateKey])
        #expect(after.tagNames == ["Red", "Work"])
        #expect(after.creationDate == created)
        var buffer = [UInt8](repeating: 0, count: 16)
        let size = getxattr(file.path, "com.example.uncial", &buffer, buffer.count, 0, 0)
        #expect(size == marker.count && Array(buffer.prefix(max(size, 0))) == marker)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
    }

    @Test func saveNowWritesImmediately() throws {
        let file = try temporaryFile("a")
        let model = DocumentViewModel(fileURL: file, initialText: "a", saveDelay: .seconds(5))
        model.updateText("b")
        model.saveNow()
        #expect(try contents(of: file) == "b")
        #expect(model.hasUnsavedChanges == false)
    }

    @Test func externalChangeIsAdoptedWhenClean() async throws {
        let file = try temporaryFile("one")
        let model = DocumentViewModel(fileURL: file, initialText: "one")
        try await Task.sleep(for: .milliseconds(150))
        try Data("two".utf8).write(to: file)
        try await Task.sleep(for: .milliseconds(600))
        #expect(model.text == "two")
        #expect(model.hasUnsavedChanges == false)
        #expect(model.body.contains("two"))
    }

    /// A file that is away for seconds (a branch switch, a sync client re-downloading it) is followed
    /// again when it comes back.
    @Test func followsTheFileBackAfterALongAbsence() async throws {
        let file = try temporaryFile("one")
        let model = DocumentViewModel(fileURL: file, initialText: "one")
        try await Task.sleep(for: .milliseconds(150))
        try FileManager.default.removeItem(at: file)
        try await Task.sleep(for: .milliseconds(1500))
        try Data("two".utf8).write(to: file)
        try await Task.sleep(for: .milliseconds(2800))
        #expect(model.text == "two")
        #expect(model.hasUnsavedChanges == false)
    }

    @Test func localEditsSurviveAConcurrentExternalChange() async throws {
        let file = try temporaryFile("one")
        let model = DocumentViewModel(fileURL: file, initialText: "one", saveDelay: .milliseconds(900))
        model.autosaves = true
        try await Task.sleep(for: .milliseconds(150))
        model.updateText("mine")
        try Data("theirs".utf8).write(to: file)
        try await Task.sleep(for: .milliseconds(500))
        #expect(model.text == "mine")
        try await Task.sleep(for: .milliseconds(900))
        #expect(try contents(of: file) == "mine")
    }

    @Test func externalChangeUnderUnsavedEditsAsksAndCanReload() async throws {
        let file = try temporaryFile("one")
        let model = DocumentViewModel(fileURL: file, initialText: "one", saveDelay: .milliseconds(300))
        model.autosaves = true
        var asked: [String] = []
        model.externalChangeResolver = { name in
            asked.append(name)
            return .reload
        }
        try await Task.sleep(for: .milliseconds(150))
        model.updateText("mine")
        try Data("theirs".utf8).write(to: file)
        try await Task.sleep(for: .milliseconds(700))
        #expect(asked == ["doc.md"])
        #expect(model.text == "theirs")
        #expect(model.hasUnsavedChanges == false)
        #expect(model.pendingExternalChange == nil)
        #expect(try contents(of: file) == "theirs")
    }

    /// While the question is open the file can change again, even back to the text it had: Reload
    /// adopts what the file holds when the answer comes, not what it held when the question was asked.
    @Test func reloadAdoptsTheFileAsItIsWhenAnswered() async throws {
        let file = try temporaryFile("one")
        let model = DocumentViewModel(fileURL: file, initialText: "one", saveDelay: .seconds(5))
        model.externalChangePolicy = .ask
        var answer: CheckedContinuation<ExternalChangeChoice, Never>?
        model.externalChangeResolver = { _ in await withCheckedContinuation { answer = $0 } }
        try await Task.sleep(for: .milliseconds(150))
        model.updateText("mine")
        try Data("theirs".utf8).write(to: file)
        try await Task.sleep(for: .milliseconds(600))
        #expect(model.pendingExternalChange == "theirs")
        try Data("one".utf8).write(to: file)
        try await Task.sleep(for: .milliseconds(600))
        #expect(model.pendingExternalChange == "one")
        answer?.resume(returning: .reload)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.text == "one")
        #expect(model.hasUnsavedChanges == false)
        #expect(try contents(of: file) == "one")
    }

    @Test func keptEditsAreWrittenOnlyAfterTheAnswer() async throws {
        let file = try temporaryFile("one")
        let model = DocumentViewModel(fileURL: file, initialText: "one", saveDelay: .milliseconds(50))
        model.autosaves = true
        model.externalChangeResolver = { _ in
            try? await Task.sleep(for: .milliseconds(400))
            return .keepLocal
        }
        try await Task.sleep(for: .milliseconds(150))
        model.updateText("mine")
        try Data("theirs".utf8).write(to: file)
        try await Task.sleep(for: .milliseconds(300))
        // The question is open: the pending save is held, the file keeps the other program's text.
        #expect(model.pendingExternalChange == "theirs")
        #expect(model.text == "mine" && model.hasUnsavedChanges == true && model.needsSavePrompt == true)
        #expect(try contents(of: file) == "theirs")
        try await Task.sleep(for: .milliseconds(500))
        #expect(model.pendingExternalChange == nil)
        #expect(try contents(of: file) == "mine")
        #expect(model.hasUnsavedChanges == false && model.needsSavePrompt == false)
    }

    @Test func saveChecksTheFileBeforeWriting() async throws {
        let file = try temporaryFile("one")
        let model = DocumentViewModel(fileURL: file, initialText: "one", saveDelay: .seconds(5))
        var asked = 0
        model.externalChangeResolver = { _ in
            asked += 1
            return .keepLocal
        }
        model.updateText("mine")
        // Written behind the watcher's back: the save must not land before the question is asked.
        try Data("theirs".utf8).write(to: file)
        model.saveNow()
        #expect(try contents(of: file) == "theirs")
        #expect(model.pendingExternalChange == "theirs")
        try await Task.sleep(for: .milliseconds(100))
        #expect(asked == 1)
        #expect(model.pendingExternalChange == nil && model.text == "mine" && model.hasUnsavedChanges == true)
        model.saveNow()
        #expect(try contents(of: file) == "mine")
    }

    @Test func silentPoliciesKeepOrReloadWithoutAsking() async throws {
        for policy in [ExternalChangePolicy.keepLocal, .reload] {
            let file = try temporaryFile("one")
            let model = DocumentViewModel(fileURL: file, initialText: "one", saveDelay: .seconds(5))
            model.externalChangePolicy = policy
            var asked = 0
            model.externalChangeResolver = { _ in
                asked += 1
                return .reload
            }
            try await Task.sleep(for: .milliseconds(150))
            model.updateText("mine")
            try Data("theirs".utf8).write(to: file)
            try await Task.sleep(for: .milliseconds(500))
            #expect(asked == 0, "\(policy)")
            #expect(model.text == (policy == .reload ? "theirs" : "mine"), "\(policy)")
            #expect(model.hasUnsavedChanges == (policy == .keepLocal), "\(policy)")
        }
    }

    @Test func remoteContentIsDisarmedUnlessAllowed() async throws {
        let markdown = "![a](https://x.test/a.png)"
        let file = try temporaryFile(markdown)
        let model = DocumentViewModel(fileURL: file, initialText: markdown, renderDelay: .milliseconds(20))
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.body.contains("data-blocked-src=\"https://x.test/a.png\""))
        model.remoteContent = true
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.body.contains("<img src=\"https://x.test/a.png\""))
    }

    @Test func reloadAdoptsDiskAndDropsPendingEdits() async throws {
        let file = try temporaryFile("one")
        let model = DocumentViewModel(fileURL: file, initialText: "one", saveDelay: .seconds(5))
        model.updateText("mine")
        try Data("disk".utf8).write(to: file)
        model.reload()
        #expect(model.text == "disk")
        #expect(model.hasUnsavedChanges == false)
        try await Task.sleep(for: .milliseconds(300))
        #expect(try contents(of: file) == "disk")
    }

    @Test func reportsSaveFailures() throws {
        let file = try temporaryFile("a")
        try FileManager.default.removeItem(at: file.deletingLastPathComponent())
        let model = DocumentViewModel(fileURL: file, initialText: "a", saveDelay: .seconds(5))
        model.updateText("b")
        model.saveNow()
        #expect(model.saveError != nil)
        #expect(model.hasUnsavedChanges == true)
    }

    /// A document renamed or moved while open is saved, and watched, where it is now; the old path
    /// is not brought back.
    @Test func followsTheFileWhenItMoves() async throws {
        let file = try temporaryFile("one")
        let model = DocumentViewModel(fileURL: file, initialText: "one", saveDelay: .seconds(5))
        let renamed = file.deletingLastPathComponent().appendingPathComponent("renamed.md")
        try FileManager.default.moveItem(at: file, to: renamed)
        model.relocate(to: renamed)
        #expect(model.fileURL == renamed)
        #expect(model.title == "renamed.md")
        model.updateText("two")
        #expect(model.saveNow() == .written)
        #expect(try contents(of: renamed) == "two")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        try await Task.sleep(for: .milliseconds(300))
        try Data("three".utf8).write(to: renamed)
        try await Task.sleep(for: .milliseconds(600))
        #expect(model.text == "three")
    }

    /// A legacy-encoded file is written back in its own encoding, so only the edited characters
    /// change; a character that encoding cannot hold makes the file UTF-8, every character kept.
    @Test func savesInTheFilesOwnEncoding() throws {
        let latin1 = Data([0x23, 0x20, 0x43, 0x61, 0x66, 0xE9, 0x0A])
        let file = try temporaryFile("")
        try latin1.write(to: file)
        let decoded = MarkdownText.read(latin1)
        let model = DocumentViewModel(fileURL: file, initialText: decoded.text, encoding: decoded.encoding, saveDelay: .seconds(5))
        model.updateText(decoded.text + "x")
        #expect(model.saveNow() == .written)
        #expect(try Data(contentsOf: file) == latin1 + Data([0x78]))
        model.updateText(model.text + "日")
        #expect(model.saveNow() == .written)
        #expect(try Data(contentsOf: file) == Data("# Café\nx日".utf8))
    }

    /// Text read with replacement characters is never written back silently: the bytes they stand
    /// for would be lost.
    @Test func doesNotWriteALossyRead() throws {
        let bytes = Data([0x23, 0x20, 0xFF, 0x0A])
        let file = try temporaryFile("")
        try bytes.write(to: file)
        let model = DocumentViewModel(fileURL: file, initialText: String(decoding: bytes, as: UTF8.self), encoding: .utf8, isLossy: true, saveDelay: .seconds(5))
        model.updateText("# edited\n")
        #expect(model.saveNow() == .failed)
        #expect(model.saveError != nil)
        #expect(try Data(contentsOf: file) == bytes)
    }

    /// A write that fails under automatic saving leaves edits nothing will write: closing and
    /// quitting must ask. Reloading drops the edits and the stale error with them.
    @Test func failedAutomaticSaveNeedsThePrompt() throws {
        let file = try temporaryFile("one")
        let directory = file.deletingLastPathComponent()
        let model = DocumentViewModel(fileURL: file, initialText: "one", saveDelay: .seconds(5))
        model.autosaves = true
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        model.updateText("two")
        #expect(model.saveNow() == .failed)
        #expect(model.saveError != nil)
        #expect(model.needsSavePrompt == true)
        model.reload()
        #expect(model.saveError == nil)
        #expect(model.needsSavePrompt == false)
    }

    /// Saving says what it did, so a closing window can tell a write from a save that waits for an
    /// answer. Before closing, a change on disk is left for the window to ask about.
    @Test func saveReportsWhatItDid() async throws {
        let file = try temporaryFile("one")
        let model = DocumentViewModel(fileURL: file, initialText: "one", saveDelay: .seconds(5))
        var asked = 0
        model.externalChangeResolver = { _ in
            asked += 1
            return .keepLocal
        }
        #expect(model.saveNow() == .unchanged)
        model.updateText("mine")
        #expect(model.saveNow() == .written)
        model.updateText("mine again")
        try Data("theirs".utf8).write(to: file)
        #expect(model.saveBeforeClosing() == .needsDecision)
        #expect(model.pendingExternalChange == "theirs")
        try await Task.sleep(for: .milliseconds(200))
        #expect(asked == 0)
        #expect(try contents(of: file) == "theirs")
        model.resolveExternalChange(.keepLocal)
        #expect(model.saveBeforeClosing() == .written)
        #expect(try contents(of: file) == "mine again")
        try await Task.sleep(for: .milliseconds(200))
        model.externalChangePolicy = .reload
        model.updateText("edited")
        try Data("theirs 2".utf8).write(to: file)
        #expect(model.saveBeforeClosing() == .adopted)
        #expect(model.text == "theirs 2")
    }

    @Test func savesOnlyOnRequestByDefault() async throws {
        let file = try temporaryFile("a")
        let model = DocumentViewModel(fileURL: file, initialText: "a", saveDelay: .milliseconds(50))
        #expect(model.autosaves == false)
        #expect(model.needsSavePrompt == false)
        model.updateText("ab")
        try await Task.sleep(for: .milliseconds(400))
        #expect(try contents(of: file) == "a")
        #expect(model.hasUnsavedChanges == true)
        #expect(model.needsSavePrompt == true)
        model.saveIfAutomatic()
        #expect(try contents(of: file) == "a")
        model.saveNow()
        #expect(try contents(of: file) == "ab")
        #expect(model.needsSavePrompt == false)
    }

    @Test func saveIfAutomaticWritesOnlyWhenAutosaving() throws {
        let file = try temporaryFile("a")
        let model = DocumentViewModel(fileURL: file, initialText: "a", saveDelay: .seconds(5))
        model.autosaves = true
        model.updateText("b")
        #expect(model.needsSavePrompt == false)
        model.saveIfAutomatic()
        #expect(try contents(of: file) == "b")
    }

    @Test func changingTheSavePolicySettlesTheFile() async throws {
        let file = try temporaryFile("a")
        let model = DocumentViewModel(fileURL: file, initialText: "a", saveDelay: .seconds(5))
        model.updateText("manual")
        model.autosaves = true
        #expect(try contents(of: file) == "manual")
        model.updateText("pending")
        model.autosaves = false
        #expect(try contents(of: file) == "pending")
        model.updateText("later")
        try await Task.sleep(for: .milliseconds(300))
        #expect(try contents(of: file) == "pending")
        #expect(model.hasUnsavedChanges == true)
    }
}
