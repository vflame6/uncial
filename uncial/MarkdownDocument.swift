import SwiftUI
import UniformTypeIdentifiers
import UncialCore

/// Read-only document model. Decoding happens off the main thread, hence `nonisolated`.
nonisolated struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown, .markdownVariant]

    var text: String
    /// How the file was read and is written back (`MarkdownText.Decoded`).
    var encoding: String.Encoding = .utf8
    var isLossy = false

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoded = MarkdownText.read(data)
        text = decoded.text
        encoding = decoded.encoding
        isLossy = decoded.isLossy
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: text.data(using: encoding, allowLossyConversion: false) ?? Data(text.utf8))
    }
}

extension UTType {
    /// The system's Markdown type, which it declares with the `md` and `markdown` extensions only.
    nonisolated static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    /// Uncial's own type for the other Markdown extensions (`mdown`, `mkd`, `mkdn`, `mkdown`, `mdwn`,
    /// `mdtxt`, `mdtext`; exported in Info.plist), conforming to the system's: a system declaration
    /// wins over an app's for the same identifier, so tags added to `net.daringfireball.markdown` are
    /// ignored and those files would otherwise resolve to dynamic types no app handles.
    nonisolated static let markdownVariant = UTType(exportedAs: "com.maksimradaev.uncial.markdown", conformingTo: .markdown)
}
