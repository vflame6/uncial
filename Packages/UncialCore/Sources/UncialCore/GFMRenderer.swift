import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Thin wrapper over cmark-gfm: Markdown → HTML fragment with GitHub extensions.
enum GFMRenderer {
    static let extensionNames = ["table", "strikethrough", "autolink", "tagfilter", "tasklist"]
    static let options: Int32 = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_VALIDATE_UTF8

    private static let registerExtensions: Void = {
        cmark_gfm_core_extensions_ensure_registered()
    }()

    /// - Parameter sourcePositions: adds `data-sourcepos` attributes to block elements.
    static func render(_ markdown: String, sourcePositions: Bool = false) -> String {
        _ = registerExtensions
        let options = sourcePositions ? self.options | CMARK_OPT_SOURCEPOS : self.options
        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in extensionNames {
            if let syntaxExtension = cmark_find_syntax_extension(name) {
                _ = cmark_parser_attach_syntax_extension(parser, syntaxExtension)
            }
        }

        let cString = markdown.utf8CString
        cString.withUnsafeBufferPointer { buffer in
            cmark_parser_feed(parser, buffer.baseAddress, buffer.count - 1)
        }

        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }

        guard let output = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser)) else {
            return ""
        }
        defer { free(output) }
        return String(cString: output)
    }
}
