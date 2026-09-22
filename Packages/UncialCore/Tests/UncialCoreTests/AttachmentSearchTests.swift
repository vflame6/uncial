import Foundation
import Testing
@testable import UncialCore

@Suite struct AttachmentSearchTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
    private let work = URL(fileURLWithPath: "/Users/someone/Notes/Work", isDirectory: true)
    private let picture = URL(fileURLWithPath: "/Users/someone/Notes/Work/img/pic.png")

    private func paths(_ urls: [URL]) -> [String] { urls.map(\.path) }

    @Test func walksUpToTheHomeFolder() {
        #expect(paths(AttachmentSearch().directories(from: work, home: home)) == [
            "/Users/someone/Notes/Work", "/Users/someone/Notes", "/Users/someone",
        ])
    }

    @Test func walksUpToTheRoot() {
        #expect(paths(AttachmentSearch(boundary: .root).directories(from: work, home: home)) == [
            "/Users/someone/Notes/Work", "/Users/someone/Notes", "/Users/someone", "/Users", "/",
        ])
    }

    @Test func staysInTheFolderOutsideHomeOrWithParentsOff() {
        let disk = URL(fileURLWithPath: "/Volumes/Disk/Notes", isDirectory: true)
        #expect(paths(AttachmentSearch().directories(from: disk, home: home)) == ["/Volumes/Disk/Notes"])
        let neighbour = URL(fileURLWithPath: "/Users/someone-else/Notes", isDirectory: true)
        #expect(paths(AttachmentSearch().directories(from: neighbour, home: home)) == ["/Users/someone-else/Notes"])
        #expect(paths(AttachmentSearch(searchesParents: false).directories(from: work, home: home)) == ["/Users/someone/Notes/Work"])
        #expect(paths(AttachmentSearch().directories(from: home, home: home)) == ["/Users/someone"])
    }

    @Test func candidatesRepeatTheRelativePathUnderEveryFolder() {
        #expect(paths(AttachmentSearch().candidates(for: picture, from: work, home: home)) == [
            "/Users/someone/Notes/Work/img/pic.png", "/Users/someone/Notes/Work/attachments/img/pic.png",
            "/Users/someone/Notes/img/pic.png", "/Users/someone/Notes/attachments/img/pic.png",
            "/Users/someone/img/pic.png", "/Users/someone/attachments/img/pic.png",
        ])
        let plainDirectory = URL(fileURLWithPath: "/Users/someone/Notes/Work")
        #expect(paths(AttachmentSearch(searchesParents: false).candidates(for: picture, from: plainDirectory, home: home)) == [
            "/Users/someone/Notes/Work/img/pic.png", "/Users/someone/Notes/Work/attachments/img/pic.png",
        ])
    }

    @Test func referencesOutsideTheFolderAreLookedForWhereTheyPoint() {
        let search = AttachmentSearch(boundary: .root)
        #expect(paths(search.candidates(for: URL(fileURLWithPath: "/Users/someone/Notes/pic.png"), from: work, home: home)) == ["/Users/someone/Notes/pic.png"])
        #expect(paths(search.candidates(for: URL(fileURLWithPath: "/etc/hosts"), from: work, home: home)) == ["/etc/hosts"])
        #expect(paths(search.candidates(for: work, from: work, home: home)) == ["/Users/someone/Notes/Work"])
    }

    @Test func blankFolderNameAndDirectLookup() {
        #expect(paths(AttachmentSearch(directoryName: " ").candidates(for: picture, from: work, home: home)) == [
            "/Users/someone/Notes/Work/img/pic.png", "/Users/someone/Notes/img/pic.png", "/Users/someone/img/pic.png",
        ])
        #expect(paths(AttachmentSearch.direct.candidates(for: picture, from: work, home: home)) == ["/Users/someone/Notes/Work/img/pic.png"])
        #expect(AttachmentSearch(directoryName: " attachments\n") == AttachmentSearch())
    }

    @Test func folderNamesMayBePathsAndDuplicatesAreListedOnce() {
        #expect(paths(AttachmentSearch(directoryName: "assets/img", searchesParents: false).candidates(for: picture, from: work, home: home)) == [
            "/Users/someone/Notes/Work/img/pic.png", "/Users/someone/Notes/Work/assets/img/img/pic.png",
        ])
        #expect(paths(AttachmentSearch(directoryName: "../shared", searchesParents: false).candidates(for: picture, from: work, home: home)) == [
            "/Users/someone/Notes/Work/img/pic.png", "/Users/someone/Notes/shared/img/pic.png",
        ])
        #expect(paths(AttachmentSearch(directoryName: "/Users/someone/Pictures").candidates(for: picture, from: work, home: home)) == [
            "/Users/someone/Notes/Work/img/pic.png", "/Users/someone/Pictures/img/pic.png",
            "/Users/someone/Notes/img/pic.png", "/Users/someone/img/pic.png",
        ])
    }

    @Test func locateReturnsTheFirstExistingCandidate() {
        let search = AttachmentSearch()
        var probed: [String] = []
        let found = search.locate(picture, from: work, home: home) { url in
            probed.append(url.path)
            return url.path == "/Users/someone/Notes/attachments/img/pic.png"
        }
        #expect(found?.path == "/Users/someone/Notes/attachments/img/pic.png")
        #expect(probed == [
            "/Users/someone/Notes/Work/img/pic.png", "/Users/someone/Notes/Work/attachments/img/pic.png",
            "/Users/someone/Notes/img/pic.png", "/Users/someone/Notes/attachments/img/pic.png",
        ])
        #expect(search.locate(picture, from: work, home: home) { _ in false } == nil)
    }

    @Test func locatesRealFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-attachments-\(UUID().uuidString)", isDirectory: true)
        let notes = root.appendingPathComponent("notes/sub", isDirectory: true)
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("attachments/pic.png"))
        let reference = notes.appendingPathComponent("pic.png")
        #expect(AttachmentSearch(boundary: .root).locate(reference, from: notes)?.standardizedFileURL.path == root.standardizedFileURL.appendingPathComponent("attachments/pic.png").path)
        #expect(AttachmentSearch(searchesParents: false).locate(reference, from: notes) == nil)
        #expect(AttachmentSearch.direct.locate(reference, from: notes) == nil)
        try Data("x".utf8).write(to: reference)
        #expect(AttachmentSearch.direct.locate(reference, from: notes)?.path == reference.standardizedFileURL.path)
    }

    @Test func relativePaths() {
        #expect(AttachmentSearch.relativePath(of: picture, from: work) == "img/pic.png")
        #expect(AttachmentSearch.relativePath(of: URL(fileURLWithPath: "/Users/someone/x.png"), from: work) == "../../x.png")
        #expect(AttachmentSearch.relativePath(of: work, from: work) == "")
        #expect(AttachmentSearch.relativePath(of: URL(fileURLWithPath: "/x.png"), from: URL(fileURLWithPath: "/", isDirectory: true)) == "x.png")
    }
}
