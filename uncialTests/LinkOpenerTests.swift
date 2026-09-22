import Foundation
import Testing
import UncialCore
@testable import Uncial

@MainActor
@Suite struct LinkOpenerTests {
    /// A link to a local file that is not where the page says opens the attachment the search finds.
    @Test func resolvesMissingFilesThroughTheAttachmentSearch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-links-\(UUID().uuidString)", isDirectory: true)
        let notes = root.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        let stored = root.appendingPathComponent("attachments/spec.pdf")
        try Data("pdf".utf8).write(to: stored)
        let link = notes.appendingPathComponent("spec.pdf")
        let everywhere = AttachmentSearch(boundary: .root)
        #expect(LinkOpener.resolve(link, from: notes, attachments: .direct).path == link.path)
        #expect(LinkOpener.resolve(link, from: nil, attachments: everywhere).path == link.path)
        #expect(LinkOpener.resolve(link, from: notes, attachments: everywhere).standardizedFileURL.path == stored.standardizedFileURL.path)
        let withFragment = try #require(URL(string: "file://\(link.path)#page=2"))
        #expect(LinkOpener.resolve(withFragment, from: notes, attachments: everywhere).standardizedFileURL.path == stored.standardizedFileURL.path)
        try Data("pdf".utf8).write(to: link)
        #expect(LinkOpener.resolve(link, from: notes, attachments: everywhere).path == link.path)
    }
}
