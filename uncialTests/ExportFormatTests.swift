import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Uncial

@MainActor
@Suite struct ExportFormatTests {
    @Test func namesTakeTheFormatsExtension() {
        #expect(ExportFormat.pdf.fileName(for: "note.md") == "note.pdf")
        #expect(ExportFormat.html.fileName(for: "Note.MARKDOWN") == "Note.html")
        #expect(ExportFormat.html.fileName(for: "note.pdf") == "note.html")
        #expect(ExportFormat.pdf.fileName(for: "v1.2") == "v1.2.pdf")
        #expect(ExportFormat.pdf.fileName(for: "") == "Untitled.pdf")
        #expect(ExportFormat.pdf.contentType == .pdf && ExportFormat.html.contentType == .html)
    }

    /// The Format popup switches the name's extension and the one type the panel allows.
    @Test func panelFollowsTheFormat() {
        let export = ExportPanel(format: .pdf, documentName: "note.md", directory: nil)
        #expect(export.panel.nameFieldStringValue == "note.pdf")
        #expect(export.panel.allowedContentTypes == [.pdf])
        export.select(.html)
        #expect(export.format == .html)
        #expect(export.panel.nameFieldStringValue == "note.html")
        #expect(export.panel.allowedContentTypes == [.html])
    }
}
