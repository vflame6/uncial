import Cocoa
import OSLog
import Quartz
import UniformTypeIdentifiers
import UncialCore

/// Data-based Quick Look preview: returns the rendered document as HTML.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private static let logger = Logger(subsystem: "com.maksimradaev.uncial", category: "quicklook")

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let fileURL = request.fileURL
        Self.logger.info("Rendering preview for \(fileURL.lastPathComponent, privacy: .public)")
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 900)) { reply in
            let data = try Data(contentsOf: fileURL)
            let markdown = MarkdownText.decode(data)
            let html = MarkdownRenderer().renderDocument(markdown, title: fileURL.lastPathComponent, baseURL: fileURL)
            reply.stringEncoding = .utf8
            reply.title = fileURL.lastPathComponent
            return Data(html.utf8)
        }
    }
}
