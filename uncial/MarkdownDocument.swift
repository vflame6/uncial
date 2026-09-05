import SwiftUI
import UniformTypeIdentifiers
import UncialCore

/// Read-only document model. Decoding happens off the main thread, hence `nonisolated`.
nonisolated struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = MarkdownText.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

extension UTType {
    nonisolated static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}
