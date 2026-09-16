import AppKit
import Testing
import UncialCore
@testable import Uncial

/// Real WebKit: the hidden mermaid.js stage the app and the Quick Look extension share.
@MainActor
@Suite(.serialized) struct DiagramWebRendererTests {
    @Test func rendersTheTypesBeautifulMermaidLacks() async throws {
        let renderer = DiagramWebRenderer()
        let store = DiagramStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("uncial-diagrams-test-\(UUID().uuidString)", isDirectory: true))
        defer { try? FileManager.default.removeItem(at: store.directory) }
        renderer.store = store
        let pieSource = "pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85"
        let ganttSource = "gantt\n  title A\n  dateFormat YYYY-MM-DD\n  section S\n  Task :a1, 2014-01-01, 30d"
        let diagrams = await renderer.render([pieSource, ganttSource, "nonsense diagram type"], theme: .github)
        #expect(diagrams.count == 2)
        let pie = try #require(diagrams[pieSource])
        #expect(pie.light.hasPrefix("<svg") && pie.light.contains("Dogs") && pie.light.contains("mermaid-light-"))
        #expect(pie.dark.contains("mermaid-dark-") && pie.light != pie.dark)
        #expect(!pie.light.contains("<script"))
        #expect(diagrams[ganttSource]?.light.contains("Task") == true)
        // The second time comes from the cache, same content; the store has it for Quick Look.
        #expect(await renderer.render([pieSource], theme: .github)[pieSource] == pie)
        #expect(store.diagrams(for: [pieSource, ganttSource], theme: .github).count == 2)
    }

    @Test func rasterizesDiagramsForLivePreview() async throws {
        let renderer = DiagramWebRenderer()
        let request = DiagramRequest(source: "graph LR\n  A --> B", theme: .macOS, dark: false, scale: 1, width: 600)
        let picture = try #require(await renderer.image(for: request))
        #expect(picture.size.width > 100 && picture.size.height > 40, "size \(picture.size)")
        let scaled = try #require(await renderer.image(for: DiagramRequest(source: "graph LR\n  A --> B", theme: .macOS, dark: true, scale: 2, width: 600)))
        #expect(scaled.size.width > picture.size.width * 1.8)
        let pie = try #require(await renderer.image(for: DiagramRequest(source: "pie\n  \"a\" : 1\n  \"b\" : 2", theme: .solarized, dark: false, scale: 1, width: 600)))
        #expect(pie.size.width > 100 && pie.size.height > 100)
        let gantt = try #require(await renderer.image(for: DiagramRequest(source: "gantt\n  dateFormat YYYY-MM-DD\n  section S\n  Task :a1, 2026-01-01, 3d", theme: .github, dark: false, scale: 1, width: 600)))
        #expect(gantt.size.width > 400, "a container-sized diagram fills the width, got \(gantt.size)")
        #expect(await renderer.image(for: DiagramRequest(source: "nonsense diagram type", theme: .macOS, dark: false, scale: 1, width: 600)) == nil)
        #expect(DiagramWebRenderer.hex(0x0A84FF) == "#0A84FF" && DiagramWebRenderer.mix(0xFFFFFF, into: 0x000000, 0.5) == 0x808080)
    }
}
