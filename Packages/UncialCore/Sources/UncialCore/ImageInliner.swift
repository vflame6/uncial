import Foundation
import UniformTypeIdentifiers

/// Rewrites relative `<img src>` references to `data:` URIs so previews work without file access.
public struct ImageInliner: Sendable {
    public let directoryURL: URL
    public let maxBytes: Int

    private static let imageSource = try! NSRegularExpression(
        pattern: #"(<img\b[^>]*?\bsrc\s*=\s*)(?:"([^"]*)"|'([^']*)')"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let scheme = try! NSRegularExpression(pattern: #"^[a-zA-Z][a-zA-Z0-9+.\-]*:"#)

    /// - Parameter baseURL: the document file (its directory is used) or a directory URL.
    public init(baseURL: URL, maxBytes: Int = 20 * 1024 * 1024) {
        self.directoryURL = baseURL.hasDirectoryPath ? baseURL : baseURL.deletingLastPathComponent()
        self.maxBytes = maxBytes
    }

    public func inline(_ html: String) -> String {
        let source = html as NSString
        var output = ""
        var cursor = 0
        for match in Self.imageSource.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let prefix = source.substring(with: match.range(at: 1))
            let doubleQuoted = match.range(at: 2).location != NSNotFound
            let value = source.substring(with: doubleQuoted ? match.range(at: 2) : match.range(at: 3))
            let quote = doubleQuoted ? "\"" : "'"
            output += prefix + quote + (dataURI(for: value) ?? value) + quote
            cursor = match.range.location + match.range.length
        }
        output += source.substring(from: cursor)
        return output
    }

    /// Resolves `source` against the directory and returns a data URI, or nil when it should be left alone.
    func dataURI(for source: String) -> String? {
        guard let fileURL = localFileURL(for: source),
              let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxBytes,
              let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType,
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    func localFileURL(for source: String) -> URL? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { return nil }
        let range = NSRange(location: 0, length: (trimmed as NSString).length)
        if Self.scheme.firstMatch(in: trimmed, range: range) != nil {
            guard trimmed.lowercased().hasPrefix("file:"), let url = URL(string: trimmed), url.isFileURL else { return nil }
            return URL(fileURLWithPath: url.path)
        }
        let allowed = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: "%?#"))
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        guard let resolved = URL(string: encoded, relativeTo: directoryURL) else { return nil }
        return URL(fileURLWithPath: resolved.path)
    }
}
