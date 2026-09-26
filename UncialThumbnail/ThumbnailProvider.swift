import AppKit
import OSLog
import QuickLookThumbnailing
import UncialCore

/// Quick Look thumbnail: the document's outline drawn as a small page, so Finder icons, the Open
/// panel's preview column and Get Info show what the document looks like instead of its source.
final class ThumbnailProvider: QLThumbnailProvider {
    private static let logger = Logger(subsystem: "com.maksimradaev.uncial", category: "thumbnail")

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let fileURL = request.fileURL
        let theme = SharedSettings.containerURL().flatMap(SharedSettings.readTheme(from:)) ?? .default
        // The page shows the first blocks only: a 64 KB prefix is more than it can hold, and reading a
        // 10 MB file whole cost 1.9 s and 300 MB.
        let text: String
        do {
            text = try MarkdownText.readPrefix(of: fileURL, maxBytes: 64 << 10)
        } catch {
            Self.logger.error("Cannot read \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            handler(nil, error)
            return
        }
        let size = ThumbnailPage.pageSize(fitting: request.maximumSize, atLeast: request.minimumSize)
        Self.logger.info("Rendering thumbnail for \(fileURL.lastPathComponent, privacy: .public) at \(Int(size.width))x\(Int(size.height)) with theme \(theme.rawValue, privacy: .public)")
        let page = ThumbnailPage(blocks: MarkdownOutline.blocks(in: text, limit: 80), palette: .light(for: theme))
        let scale = request.scale
        handler(QLThumbnailReply(contextSize: size) { context in
            page.draw(in: size, scale: scale, context: context)
            return true
        }, nil)
    }
}
