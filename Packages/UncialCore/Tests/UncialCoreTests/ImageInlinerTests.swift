import Foundation
import Testing
@testable import UncialCore

@Suite struct ImageInlinerTests {
    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-img-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("img"), withIntermediateDirectories: true)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        try png.write(to: directory.appendingPathComponent("img/dot.png"))
        try Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8).write(to: directory.appendingPathComponent("img/my icon.svg"))
        return directory
    }

    @Test func inlinesRelativeImages() throws {
        let inliner = ImageInliner(baseURL: try fixtureDirectory().appendingPathComponent("README.md"))
        let html = "<p><img src=\"img/dot.png\" alt=\"dot\" /> <img src='./img/my%20icon.svg'></p>"
        let output = inliner.inline(html)
        #expect(output.contains("<img src=\"data:image/png;base64,iVBORw0KGgo"))
        #expect(output.contains("alt=\"dot\" />"))
        #expect(output.contains("<img src='data:image/svg+xml;base64,"))
    }

    @Test func leavesRemoteMissingOversizedAndDataAlone() throws {
        let inliner = ImageInliner(baseURL: try fixtureDirectory().appendingPathComponent("README.md"), maxBytes: 10)
        let html = "<img src=\"https://example.com/a.png\"><img src=\"img/missing.png\"><img src=\"img/dot.png\"><img src=\"data:image/png;base64,AAAA\">"
        #expect(inliner.inline(html) == html)
    }

    @Test func stripsQueryAndFragment() throws {
        let inliner = ImageInliner(baseURL: try fixtureDirectory().appendingPathComponent("README.md"))
        let output = inliner.inline("<img src=\"img/dot.png?raw=true#gh-light-mode-only\">")
        #expect(output.hasPrefix("<img src=\"data:image/png;base64,"))
    }

    @Test func leavesNonImageFilesAlone() throws {
        let directory = try fixtureDirectory()
        try Data("secret".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        let inliner = ImageInliner(baseURL: directory.appendingPathComponent("README.md"))
        let html = "<img src=\"notes.txt\">"
        #expect(inliner.inline(html) == html)
    }
}
