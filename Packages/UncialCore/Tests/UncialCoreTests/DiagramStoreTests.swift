import Foundation
import Testing
@testable import UncialCore

@Suite struct DiagramStoreTests {
    private let directory = TemporaryDirectory()

    @Test func roundTripsPerThemeAndSource() throws {
        let store = DiagramStore(directory: directory.url("diagrams", isDirectory: true))
        let pie = PreRenderedDiagram(light: "<svg id=\"l\"/>", dark: "<svg id=\"d\"/>")
        store.save(["pie\n  \"a\" : 1": pie], theme: .github)
        #expect(store.diagrams(for: ["pie\n  \"a\" : 1", "gantt"], theme: .github) == ["pie\n  \"a\" : 1": pie])
        #expect(store.diagrams(for: ["pie\n  \"a\" : 1"], theme: .macOS).isEmpty)
        #expect(DiagramStore.name(for: "x", theme: .macOS) != DiagramStore.name(for: "x", theme: .github))
        #expect(DiagramStore(directory: directory.url("never-written", isDirectory: true)).diagrams(for: ["anything"], theme: .macOS).isEmpty)
    }

    @Test func keepsOnlyTheNewestFiles() throws {
        let store = DiagramStore(directory: directory.url("diagrams", isDirectory: true))
        var batch: [String: PreRenderedDiagram] = [:]
        for index in 0..<(DiagramStore.limit + 5) {
            batch["diagram \(index)"] = PreRenderedDiagram(light: "l", dark: "d")
        }
        store.save(batch, theme: .solarized)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(files.count == DiagramStore.limit)
    }
}
