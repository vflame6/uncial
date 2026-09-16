import Foundation
import Testing
@testable import UncialCore

@Suite struct DiagramStoreTests {
    private func temporaryStore() -> DiagramStore {
        DiagramStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("uncial-diagrams-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func roundTripsPerThemeAndSource() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let pie = PreRenderedDiagram(light: "<svg id=\"l\"/>", dark: "<svg id=\"d\"/>")
        store.save(["pie\n  \"a\" : 1": pie], theme: .github)
        #expect(store.diagrams(for: ["pie\n  \"a\" : 1", "gantt"], theme: .github) == ["pie\n  \"a\" : 1": pie])
        #expect(store.diagrams(for: ["pie\n  \"a\" : 1"], theme: .macOS).isEmpty)
        #expect(DiagramStore.name(for: "x", theme: .macOS) != DiagramStore.name(for: "x", theme: .github))
        #expect(DiagramStore.name(for: "x", theme: .macOS).count == 64)
        #expect(temporaryStore().diagrams(for: ["anything"], theme: .macOS).isEmpty)
    }

    @Test func keepsOnlyTheNewestFiles() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var batch: [String: PreRenderedDiagram] = [:]
        for index in 0..<(DiagramStore.limit + 5) {
            batch["diagram \(index)"] = PreRenderedDiagram(light: "l", dark: "d")
        }
        store.save(batch, theme: .solarized)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(files.count == DiagramStore.limit)
    }
}
