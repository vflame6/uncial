import AppKit
import Network
import Testing
import UncialCore
@testable import Uncial

/// A TCP listener on 127.0.0.1 that counts the connections it gets and drops them.
final class LoopbackListener: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var accepted = 0

    var connections: Int { lock.withLock { accepted } }
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.count()
            connection.cancel()
        }
    }

    private func count() {
        lock.withLock { accepted += 1 }
    }

    func start() async {
        let ready = AsyncStream<Void> { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled:
                    continuation.yield()
                    continuation.finish()
                default:
                    break
                }
            }
        }
        listener.start(queue: DispatchQueue(label: "uncial-tests-loopback"))
        for await _ in ready { break }
    }

    func stop() {
        listener.cancel()
    }
}

/// Real WebKit: the hidden mermaid.js stage the app and the Quick Look extension share.
@MainActor
@Suite(.serialized) struct DiagramWebRendererTests {
    /// The stage needs no network: a diagram naming a web image (mermaid's image shape; front
    /// matter sends any flowchart to mermaid.js) must not reach the server, whatever the setting.
    @Test func stageLoadsNothingFromTheWeb() async throws {
        let listener = try LoopbackListener()
        await listener.start()
        defer { listener.stop() }
        let url = "http://127.0.0.1:\(listener.port)/beacon.png"
        let source = "---\ntitle: Beacon\n---\nflowchart TD\n    A@{ img: \"\(url)\", label: \"x\", pos: \"t\", w: 60, h: 60, constraint: \"off\" }\n    A --> B"
        let renderer = DiagramWebRenderer()
        _ = await renderer.render([source], theme: .github)
        _ = await renderer.image(for: DiagramRequest(source: source, theme: .github, dark: false, scale: 1, width: 600))
        try await Task.sleep(for: .milliseconds(500))
        #expect(listener.connections == 0)
        // Control: the listener does count connections (URLSession retries a dropped one).
        _ = try? await URLSession.shared.data(from: URL(string: url)!)
        try await Task.sleep(for: .milliseconds(200))
        #expect(listener.connections >= 1)
    }

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

    @Test func rasterizesMathForLivePreview() async throws {
        let renderer = DiagramWebRenderer()
        let request = MathRequest(tex: "\\frac{a}{b}", display: false, theme: .macOS, dark: false, fontSize: 13)
        let fraction = try #require(await renderer.picture(for: request))
        #expect(fraction.size.width > 5 && fraction.size.height > 20 && fraction.baseline > 5 && fraction.baseline < fraction.size.height, "size \(fraction.size) baseline \(fraction.baseline)")
        #expect(fraction.image.size == fraction.size)
        let bigger = try #require(await renderer.picture(for: MathRequest(tex: "\\frac{a}{b}", display: false, theme: .macOS, dark: true, fontSize: 26)))
        #expect(bigger.size.height > fraction.size.height * 1.6, "\(bigger.size) vs \(fraction.size)")
        let display = try #require(await renderer.picture(for: MathRequest(tex: "\\sum_{n=1}^{\\infty} \\frac{1}{n^2}", display: true, theme: .github, dark: false, fontSize: 13)))
        #expect(display.size.width > 30 && display.size.height > 30 && display.baseline > 0, "\(display.size)")
        // Bad TeX comes back as KaTeX's red source, not nil.
        let bad = try #require(await renderer.picture(for: MathRequest(tex: "\\frac{1}", display: false, theme: .solarized, dark: false, fontSize: 13)))
        #expect(bad.size.width > 10)
        #expect(await renderer.picture(for: request) === fraction)
        // Transparent, so the editor's selection shows through.
        let tiff = try #require(fraction.image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let corner = try #require(bitmap.colorAt(x: 0, y: 0))
        #expect(corner.alphaComponent < 0.01, "corner alpha \(corner.alphaComponent)")
    }
}
