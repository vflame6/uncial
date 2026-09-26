import AppKit
import Testing
import UncialCore
@testable import Uncial

/// Records what the opener asks NSWorkspace to do.
@MainActor
final class FakeLinkWorkspace: LinkWorkspace {
    var opened: [URL] = []
    var revealed: [URL] = []
    var handler: URL? = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")

    func open(_ url: URL) -> Bool {
        opened.append(url)
        return true
    }

    func activateFileViewerSelecting(_ fileURLs: [URL]) {
        revealed += fileURLs
    }

    func urlForApplication(toOpen url: URL) -> URL? {
        handler
    }
}

@MainActor
@Suite struct LinkOpenerTests {
    private func kind(_ action: LinkOpener.Action) -> String {
        switch action {
        case .open: "open"
        case .openDocument: "document"
        case .confirm: "confirm"
        case .reveal: "reveal"
        }
    }

    /// Web and mail links and Markdown files open; other files and URL schemes ask first; programs,
    /// scripts, apps and installers never open from a link (a `.command` next to a cloned README
    /// would run in Terminal), they can only be shown in Finder.
    @Test func decidesWhatAClickDoes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-links-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func file(_ name: String, _ contents: String, executable: Bool = false) throws -> URL {
            let url = folder.appendingPathComponent(name)
            try Data(contents.utf8).write(to: url)
            if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
            return url
        }
        let app = folder.appendingPathComponent("Tool.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        func action(_ url: URL) -> String { kind(LinkOpener.action(for: url, from: folder, attachments: .direct)) }

        #expect(action(URL(string: "https://example.com/a")!) == "open")
        #expect(action(URL(string: "mailto:someone@example.com")!) == "open")
        #expect(action(URL(string: "ssh://example.invalid")!) == "confirm")
        #expect(action(URL(string: "x-man-page://ls")!) == "confirm")
        #expect(action(try file("notes.md", "# Notes")) == "document")
        #expect(action(try file("spec.pdf", "%PDF-1.4\n")) == "confirm")
        #expect(action(try file("setup.command", "#!/bin/sh\necho hi\n", executable: true)) == "reveal")
        #expect(action(try file("build.sh", "#!/bin/sh\n")) == "reveal")
        #expect(action(try file("tool.py", "print(1)\n")) == "reveal")
        #expect(action(try file("Installer.pkg", "x")) == "reveal")
        #expect(action(app) == "reveal")
    }

    /// Asking comes first: a declined question opens nothing, and a program is at most shown in Finder.
    @Test func asksBeforeOpeningAndNeverRunsPrograms() {
        let workspace = FakeLinkWorkspace()
        var questions: [LinkOpener.Question] = []
        var answer = false
        let ask: (LinkOpener.Question, NSWindow?, @escaping (Bool) -> Void) -> Void = { question, _, reply in
            questions.append(question)
            reply(answer)
        }
        let script = URL(fileURLWithPath: "/tmp/uncial-links/setup.command")
        let ssh = URL(string: "ssh://example.invalid")!
        let web = URL(string: "https://example.com")!

        LinkOpener.perform(.reveal(script), in: nil, workspace: workspace, ask: ask)
        LinkOpener.perform(.confirm(ssh), in: nil, workspace: workspace, ask: ask)
        #expect(workspace.opened.isEmpty && workspace.revealed.isEmpty)
        #expect(questions.count == 2)
        #expect(questions[0].message.contains("setup.command"))
        #expect(questions[1].detail.contains("Terminal"))

        answer = true
        LinkOpener.perform(.reveal(script), in: nil, workspace: workspace, ask: ask)
        #expect(workspace.opened.isEmpty && workspace.revealed == [script])
        LinkOpener.perform(.confirm(ssh), in: nil, workspace: workspace, ask: ask)
        #expect(workspace.opened == [ssh])

        LinkOpener.perform(.open(web), in: nil, workspace: workspace, ask: ask)
        #expect(workspace.opened == [ssh, web])
        #expect(questions.count == 4)
    }
    /// A link to a local file that is not where the page says opens the attachment the search finds.
    @Test func resolvesMissingFilesThroughTheAttachmentSearch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-links-\(UUID().uuidString)", isDirectory: true)
        let notes = root.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        let stored = root.appendingPathComponent("attachments/spec.pdf")
        try Data("pdf".utf8).write(to: stored)
        let link = notes.appendingPathComponent("spec.pdf")
        let everywhere = AttachmentSearch(boundary: .root)
        #expect(LinkOpener.resolve(link, from: notes, attachments: .direct).path == link.path)
        #expect(LinkOpener.resolve(link, from: nil, attachments: everywhere).path == link.path)
        #expect(LinkOpener.resolve(link, from: notes, attachments: everywhere).standardizedFileURL.path == stored.standardizedFileURL.path)
        let withFragment = try #require(URL(string: "file://\(link.path)#page=2"))
        #expect(LinkOpener.resolve(withFragment, from: notes, attachments: everywhere).standardizedFileURL.path == stored.standardizedFileURL.path)
        try Data("pdf".utf8).write(to: link)
        #expect(LinkOpener.resolve(link, from: notes, attachments: everywhere).path == link.path)
    }
}
