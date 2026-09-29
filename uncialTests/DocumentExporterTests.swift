import AppKit
import PDFKit
import Testing
import UncialCore
@testable import Uncial

@MainActor
@Suite(.serialized) final class DocumentExporterTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-export-\(UUID().uuidString)", isDirectory: true)

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func snapshot(_ text: String) -> ExportSnapshot {
        ExportSnapshot(text: text, fileURL: folder.appendingPathComponent("note.md"), theme: .macOS, remoteContent: false, attachments: .direct)
    }

    /// The window's text goes out as it is, unsaved edits included, named after the document.
    @Test func snapshotTakesTheEditorsText() {
        let model = DocumentViewModel(fileURL: folder.appendingPathComponent("note.md"), initialText: "saved", starts: false)
        model.updateText("typed")
        let snapshot = ExportSnapshot(model: model)
        #expect(snapshot.text == "typed" && snapshot.fileName == "note.md" && snapshot.title == "note")
    }

    /// The HTML page stands on its own: styles, the local picture inlined, no WebKit-only colors, a
    /// policy that keeps script off; a second export replaces the first.
    @Test func writesAStandaloneHTMLPage() async throws {
        try Data(base64Encoded: "R0lGODlhAQABAAAAACw=")!.write(to: folder.appendingPathComponent("dot.gif"))
        let url = folder.appendingPathComponent("note.html")
        try await DocumentExporter.write(snapshot("# Title\n\nFirst *text*.\n\n![dot](dot.gif)"), as: .html, to: url)
        try await DocumentExporter.write(snapshot("# Title\n\nSome *text*.\n\n![dot](dot.gif)"), as: .html, to: url)
        let html = try String(contentsOf: url, encoding: .utf8)
        #expect(html.contains("<title>note</title>"))
        #expect(html.contains("Some <em>text</em>.") && !html.contains("First"))
        #expect(html.contains("src=\"data:image/gif;base64,"))
        #expect(html.contains("http-equiv=\"Content-Security-Policy\""))
        #expect(!html.contains("-apple-system-") && html.contains("--system-label: rgba("))
    }

    /// A diagram only mermaid.js draws goes out as a picture, light and dark, not as its source.
    @Test func exportsDiagramsOnlyMermaidJSDraws() async throws {
        let url = folder.appendingPathComponent("pie.html")
        try await DocumentExporter.write(snapshot("```mermaid\npie title Pets\n    \"Dogs\" : 3\n    \"Cats\" : 2\n```"), as: .html, to: url)
        let html = try String(contentsOf: url, encoding: .utf8)
        #expect(html.contains("<figure class=\"mermaid\"><div class=\"light\">"))
        #expect(!html.contains("pie title Pets</code>"))
    }

    /// A large flowchart is laid out off the main actor, as the window's render does it (PERF-8): on the
    /// main thread the layout froze the window for a second and more, and beautiful-mermaid's context,
    /// made there, left its collector's timers on the main run loop to wait out every later layout.
    @Test func exportLaysOutDiagramsOffTheMainActor() async throws {
        let run = UUID().uuidString.prefix(8)
        let edges = (0..<70).map { "  N\($0)[\"\(run) \($0)\"] --> N\($0 + 1)\n  N\($0) --> M\($0 % 9)" }.joined(separator: "\n")
        let url = folder.appendingPathComponent("flowchart.html")
        var finished = false
        let exporting = Task { @MainActor in
            try await DocumentExporter.write(snapshot("```mermaid\ngraph TD\n\(edges)\n```"), as: .html, to: url)
            finished = true
        }
        let start = ContinuousClock.now
        var last = start
        var longest: Duration = .zero
        while !finished, ContinuousClock.now - start < .seconds(60) {
            try await Task.sleep(for: .milliseconds(5))
            let now = ContinuousClock.now
            longest = max(longest, now - last)
            last = now
        }
        try await exporting.value
        #expect(try String(contentsOf: url, encoding: .utf8).contains("<figure class=\"mermaid\"><svg"))
        // Other suites' main-actor tests run in between in a full run (up to about 0.3 s).
        #expect(longest < .milliseconds(600), "the main actor stalled \(longest)")
    }

    @Test func writesAPDF() async throws {
        let url = folder.appendingPathComponent("note.pdf")
        try await DocumentExporter.write(snapshot("# Title\n\nUnsaved words."), as: .pdf, to: url)
        let document = try #require(PDFDocument(url: url))
        #expect(document.string?.contains("Unsaved words.") == true)
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "note")
    }

    /// A failed write reaches the user, and the menu item comes back.
    @Test func reportsAFailure() async {
        let exporter = DocumentExporter()
        var reported: Error?
        exporter.reportError = { error, _ in reported = error }
        await exporter.export(snapshot("# Title"), as: .html, to: folder.appendingPathComponent("missing/note.html"), window: nil)
        #expect(reported != nil)
        #expect(exporter.isRunning == false)
    }
}
