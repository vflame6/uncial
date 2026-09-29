import Foundation
import Testing
import UncialCore
import UniformTypeIdentifiers
@testable import Uncial

/// The Markdown files the app opens: the system's type and the variant type the app exports.
@Suite struct MarkdownDocumentTests {
    @Test func opensTheStandardTypeAndItsVariant() {
        #expect(UTType.markdown.identifier == "net.daringfireball.markdown")
        #expect(UTType.markdownVariant.identifier == "com.maksimradaev.uncial.markdown")
        #expect(UTType.markdownVariant.conforms(to: .markdown))
        #expect(MarkdownDocument.readableContentTypes == [.markdown, .markdownVariant])
    }

    /// The extensions links, pasted files and exports take for Markdown (`MarkdownText.fileExtensions`)
    /// are those of the types the app declares in its Info.plist.
    @Test func markdownExtensionsAreTheDeclaredTypesTags() {
        let declarations = ["UTExportedTypeDeclarations", "UTImportedTypeDeclarations"]
            .flatMap { Bundle.main.infoDictionary?[$0] as? [[String: Any]] ?? [] }
        let tags = declarations.flatMap { ($0["UTTypeTagSpecification"] as? [String: Any])?["public.filename-extension"] as? [String] ?? [] }
        #expect(Set(tags) == MarkdownText.fileExtensions)
    }
}
