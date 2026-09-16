import Foundation
import Testing
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
