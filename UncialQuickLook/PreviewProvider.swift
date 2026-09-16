import Cocoa
import OSLog
import Quartz
import UniformTypeIdentifiers
import UncialCore

/// Data-based Quick Look preview: returns the rendered document as HTML. Diagrams beautiful-mermaid
/// cannot draw come from the App Group store the app fills when it renders them (WebKit cannot run
/// in this sandbox), so the HTML still carries no script; unseen ones stay code blocks.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private static let logger = Logger(subsystem: "com.maksimradaev.uncial", category: "quicklook")

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let fileURL = request.fileURL
        let theme = SharedSettings.containerURL().flatMap(SharedSettings.readTheme(from:)) ?? .default
        Self.logger.info("Rendering preview for \(fileURL.lastPathComponent, privacy: .public) with theme \(theme.rawValue, privacy: .public)")
        let data = try Data(contentsOf: fileURL)
        let markdown = MarkdownText.decode(data)
        let sources = MermaidRenderer.unsupportedFences(in: markdown)
        var diagrams: [String: PreRenderedDiagram] = [:]
        if !sources.isEmpty {
            diagrams = DiagramStore.shared?.diagrams(for: sources, theme: theme) ?? [:]
            Self.logger.info("Found \(diagrams.count, privacy: .public) of \(sources.count, privacy: .public) stored diagrams")
        }
        let html = MarkdownRenderer().renderDocument(markdown, title: fileURL.lastPathComponent, baseURL: fileURL, theme: theme, diagrams: diagrams)
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 900)) { reply in
            reply.stringEncoding = .utf8
            reply.title = fileURL.lastPathComponent
            return Data(html.utf8)
        }
    }
}
