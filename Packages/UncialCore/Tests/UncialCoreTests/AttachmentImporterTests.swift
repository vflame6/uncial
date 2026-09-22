import Foundation
import Testing
@testable import UncialCore

@Suite struct AttachmentImporterTests {
    /// `root/notes/sub/` holds the document, `root/attachments/` exists, `elsewhere/` holds sources.
    private struct Fixture {
        let root: URL
        let sub: URL
        let elsewhere: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-import-\(UUID().uuidString)", isDirectory: true)
            sub = root.appendingPathComponent("notes/sub", isDirectory: true)
            elsewhere = root.appendingPathComponent("elsewhere", isDirectory: true)
            for folder in [sub, elsewhere, root.appendingPathComponent("attachments", isDirectory: true)] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
        }

        func file(_ path: String, _ contents: String = "x") throws -> URL {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
            return url
        }

        func path(_ url: URL) -> String { url.standardizedFileURL.path }
        func relative(_ url: URL) -> String { AttachmentSearch.relativePath(of: url, from: root) }
    }

    private let everywhere = AttachmentSearch(boundary: .root)

    @Test func targetFolderPerDestination() throws {
        let fixture = try Fixture()
        let sub = fixture.sub
        #expect(fixture.relative(AttachmentImporter(search: everywhere).targetDirectory(for: sub)) == "notes/sub/attachments")
        #expect(fixture.relative(AttachmentImporter(search: everywhere, destination: .documentFolder).targetDirectory(for: sub)) == "notes/sub")
        #expect(fixture.relative(AttachmentImporter(search: everywhere, destination: .nearestAttachmentsFolder).targetDirectory(for: sub)) == "attachments")
        let ownOnly = AttachmentSearch(searchesParents: false)
        #expect(fixture.relative(AttachmentImporter(search: ownOnly, destination: .nearestAttachmentsFolder).targetDirectory(for: sub)) == "notes/sub/attachments")
        try FileManager.default.createDirectory(at: sub.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        #expect(fixture.relative(AttachmentImporter(search: everywhere, destination: .nearestAttachmentsFolder).targetDirectory(for: sub)) == "notes/sub/attachments")
        let blank = AttachmentSearch(directoryName: " ", boundary: .root)
        for destination in AttachmentImporter.Destination.allCases {
            #expect(fixture.relative(AttachmentImporter(search: blank, destination: destination).targetDirectory(for: sub)) == "notes/sub")
        }
        let shared = AttachmentSearch(directoryName: "../shared", searchesParents: false)
        #expect(fixture.relative(AttachmentImporter(search: shared).targetDirectory(for: sub)) == "notes/shared")
    }

    @Test func copiesOutsideFilesIntoACreatedFolderUnderFreeNames() throws {
        let fixture = try Fixture()
        let importer = AttachmentImporter(search: everywhere)
        let first = try fixture.file("elsewhere/pic.png", "one")
        let stored = try importer.store(fileAt: first, for: fixture.sub)
        #expect(fixture.relative(stored) == "notes/sub/attachments/pic.png")
        #expect(try String(contentsOf: stored, encoding: .utf8) == "one")
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(fixture.relative(try importer.store(fileAt: first, for: fixture.sub)) == "notes/sub/attachments/pic.png")
        let other = try fixture.file("other/pic.png", "two")
        #expect(fixture.relative(try importer.store(fileAt: other, for: fixture.sub)) == "notes/sub/attachments/pic 2.png")
        let third = try fixture.file("third/pic.png", "three")
        #expect(fixture.relative(try importer.store(fileAt: third, for: fixture.sub)) == "notes/sub/attachments/pic 3.png")
        let bare = try fixture.file("elsewhere/README", "readme")
        #expect(fixture.relative(try importer.store(fileAt: bare, for: fixture.sub)) == "notes/sub/attachments/README")
        #expect(fixture.relative(try importer.store(fileAt: try fixture.file("x/README", "other"), for: fixture.sub)) == "notes/sub/attachments/README 2")
    }

    @Test func linksReachableFilesWhereTheyAre() throws {
        let fixture = try Fixture()
        let importer = AttachmentImporter(search: everywhere)
        let inside = try fixture.file("notes/sub/img/x.png")
        #expect(fixture.path(try importer.store(fileAt: inside, for: fixture.sub)) == fixture.path(inside))
        let covered = try fixture.file("attachments/y.png")
        #expect(fixture.path(try importer.store(fileAt: covered, for: fixture.sub)) == fixture.path(covered))
        let note = try fixture.file("elsewhere/note.md")
        #expect(fixture.path(try importer.store(fileAt: note, for: fixture.sub)) == fixture.path(note))
        // With the walk stopping at home (the fixture lies outside it) the parent's folder is not covered.
        let homeBound = AttachmentImporter(search: AttachmentSearch())
        #expect(fixture.relative(try homeBound.store(fileAt: covered, for: fixture.sub)) == "notes/sub/attachments/y.png")
        let blank = AttachmentImporter(search: AttachmentSearch(directoryName: "", boundary: .root))
        #expect(fixture.relative(try blank.store(fileAt: covered, for: fixture.sub)) == "notes/sub/y.png")
    }

    @Test func storesPictureData() throws {
        let fixture = try Fixture()
        let importer = AttachmentImporter(search: everywhere, destination: .documentFolder)
        let data = Data("png".utf8)
        let stored = try importer.store(data, named: "pasted.png", for: fixture.sub)
        #expect(fixture.relative(stored) == "notes/sub/pasted.png")
        #expect(try Data(contentsOf: stored) == data)
        #expect(fixture.relative(try importer.store(data, named: "pasted.png", for: fixture.sub)) == "notes/sub/pasted.png")
        #expect(fixture.relative(try importer.store(Data("other".utf8), named: "pasted.png", for: fixture.sub)) == "notes/sub/pasted 2.png")
    }

    @Test func markdownForImagesAndFiles() throws {
        let fixture = try Fixture()
        let sub = fixture.sub
        #expect(AttachmentImporter.markdown(for: sub.appendingPathComponent("attachments/pic.png"), relativeTo: sub) == "![pic](attachments/pic.png)")
        #expect(AttachmentImporter.markdown(for: sub.appendingPathComponent("attachments/spec v2 (final).pdf"), relativeTo: sub) == "[spec v2 (final).pdf](attachments/spec%20v2%20%28final%29.pdf)")
        #expect(AttachmentImporter.markdown(for: fixture.root.appendingPathComponent("attachments/a#1.jpeg"), relativeTo: sub) == "![a#1](../../attachments/a%231.jpeg)")
        #expect(AttachmentImporter.markdown(for: sub.appendingPathComponent("[draft].md"), relativeTo: sub) == "[\\[draft\\].md](%5Bdraft%5D.md)")
        #expect(AttachmentImporter.markdown(for: sub.appendingPathComponent("attachments/README"), relativeTo: sub) == "[README](attachments/README)")
        #expect(AttachmentImporter.linkDestination(for: sub.appendingPathComponent("100%.txt"), relativeTo: sub) == "100%25.txt")
    }

    @Test func pastedImageNameCarriesTheTime() throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 15, minute: 30, second: 12)))
        #expect(AttachmentImporter.pastedImageName(extension: "png", date: date) == "pasted-image-20260922-153012.png")
        #expect(AttachmentImporter.pastedImageName(extension: "jpg", date: date).hasSuffix(".jpg"))
    }
}
