import Foundation

public enum MarkdownText {
    /// The file extensions Uncial treats as Markdown (lowercase): the system's for
    /// `net.daringfireball.markdown` plus the app's exported variant type's tags.
    public static let fileExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mkdown", "mdwn", "mdtxt", "mdtext"]

    /// A file's text and how to write it back.
    public struct Decoded: Equatable, Sendable {
        public let text: String
        /// What saving writes: UTF-8 for UTF-8 and UTF-16 files (a BOM is not kept), the file's own
        /// encoding for a legacy one (Latin-1, Windows-1252, Shift-JIS, …), so its bytes survive.
        public let encoding: String.Encoding
        /// No encoding read the bytes without loss: the text has U+FFFD where they were, and
        /// writing it would replace them.
        public let isLossy: Bool

        public init(text: String, encoding: String.Encoding, isLossy: Bool) {
            self.text = text
            self.encoding = encoding
            self.isLossy = isLossy
        }
    }

    /// The text of `read(_:)`.
    public static func decode(_ data: Data) -> String {
        read(data).text
    }

    /// UTF-8 (BOM stripped), UTF-16 when a BOM says so, then `preferred` (the encoding the file was
    /// read with before, so a re-read of the app's own write matches), then the legacy encoding
    /// Foundation detects that reads every byte; lossy UTF-8 only when none does.
    public static func read(_ data: Data, preferring preferred: String.Encoding? = nil) -> Decoded {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data.dropFirst(3), encoding: .utf8) {
            return Decoded(text: text, encoding: .utf8, isLossy: false)
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return Decoded(text: text, encoding: .utf8, isLossy: false)
        }
        if let text = String(data: data, encoding: .utf8) {
            return Decoded(text: text, encoding: .utf8, isLossy: false)
        }
        if let preferred, preferred != .utf8, let text = String(data: data, encoding: preferred),
           text.data(using: preferred) == data {
            return Decoded(text: text, encoding: preferred, isLossy: false)
        }
        var converted: NSString?
        var usedLossy: ObjCBool = false
        let detected = NSString.stringEncoding(for: data, encodingOptions: [.allowLossyKey: false],
                                               convertedString: &converted, usedLossyConversion: &usedLossy)
        if detected != 0, let converted, !usedLossy.boolValue {
            let encoding = String.Encoding(rawValue: detected)
            let text = converted as String
            if text.data(using: encoding) == data {
                return Decoded(text: text, encoding: encoding, isLossy: false)
            }
        }
        return Decoded(text: String(decoding: data, as: UTF8.self), encoding: .utf8, isLossy: true)
    }
}
