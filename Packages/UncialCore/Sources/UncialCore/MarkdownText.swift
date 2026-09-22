import Foundation

public enum MarkdownText {
    /// The file extensions Uncial treats as Markdown (lowercase): the system's for
    /// `net.daringfireball.markdown` plus the app's exported variant type's tags.
    public static let fileExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mkdown", "mdwn", "mdtxt", "mdtext"]

    /// UTF-8 (BOM stripped), UTF-16 when a BOM says so, otherwise lossy UTF-8.
    public static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data.dropFirst(3), encoding: .utf8) {
            return text
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }
}
