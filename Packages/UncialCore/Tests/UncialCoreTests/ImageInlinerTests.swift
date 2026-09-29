import Foundation
import Testing
@testable import UncialCore

@Suite struct ImageInlinerTests {
    private static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
    private static let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"/>"
    private let directory = TemporaryDirectory()

    /// A document with `img/dot.png` and `img/my icon.svg` next to it.
    private func document() throws -> URL {
        try directory.file("img/dot.png", Self.png)
        try directory.file("img/my icon.svg", Self.svg)
        return directory.url("README.md")
    }

    @Test func inlinesRelativeImages() throws {
        let inliner = ImageInliner(baseURL: try document())
        let html = "<p><img src=\"img/dot.png\" alt=\"dot\" /> <img src='./img/my%20icon.svg'></p>"
        let output = inliner.inline(html)
        #expect(output.contains("<img src=\"data:image/png;base64,iVBORw0KGgo"))
        #expect(output.contains("alt=\"dot\" />"))
        #expect(output.contains("<img src='data:image/svg+xml;base64,"))
    }

    @Test func leavesRemoteMissingOversizedAndDataAlone() throws {
        let inliner = ImageInliner(baseURL: try document(), maxBytes: 10)
        let html = "<img src=\"https://example.com/a.png\"><img src=\"img/missing.png\"><img src=\"img/dot.png\"><img src=\"data:image/png;base64,AAAA\">"
        #expect(inliner.inline(html) == html)
    }

    @Test func stripsQueryAndFragment() throws {
        let inliner = ImageInliner(baseURL: try document())
        let output = inliner.inline("<img src=\"img/dot.png?raw=true#gh-light-mode-only\">")
        #expect(output.hasPrefix("<img src=\"data:image/png;base64,"))
    }

    /// A missing image is found in the document folder's attachments folder, or in a parent's.
    @Test func findsImagesThroughTheAttachmentSearch() throws {
        try directory.file("notes/attachments/dot.png", Self.png)
        try directory.file("notes/sub/attachments/my icon.svg", Self.svg)
        let document = directory.url("notes/sub/README.md")
        let html = "<img src=\"dot.png\"><img src=\"my%20icon.svg\">"
        #expect(ImageInliner(baseURL: document).inline(html) == html)
        let everywhere = ImageInliner(baseURL: document, attachments: AttachmentSearch(boundary: .root)).inline(html)
        #expect(everywhere.contains("<img src=\"data:image/png;base64,iVBORw0KGgo") && everywhere.contains("<img src=\"data:image/svg+xml;base64,"))
        let ownFolder = ImageInliner(baseURL: document, attachments: AttachmentSearch(searchesParents: false)).inline(html)
        #expect(ownFolder.contains("<img src=\"dot.png\">") && ownFolder.contains("<img src=\"data:image/svg+xml;base64,"))
    }

    @Test func leavesNonImageFilesAlone() throws {
        try directory.file("notes.txt", "secret")
        let html = "<img src=\"notes.txt\">"
        #expect(ImageInliner(baseURL: try document()).inline(html) == html)
    }
}
