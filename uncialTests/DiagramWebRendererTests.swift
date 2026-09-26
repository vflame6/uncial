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

/// The first answer a waiting test gets: the value, or nil from the deadline.
@MainActor private final class FirstAnswer<T> {
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) {
        self.continuation = continuation
    }

    func give(_ value: T?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

/// Real WebKit: the hidden mermaid.js stage the app and the Quick Look extension share.
@MainActor
@Suite(.serialized) struct DiagramWebRendererTests {
    /// `body`'s value, or nil after `seconds`: a test fails instead of hanging on a stage that does.
    private func within<T>(_ seconds: Double, _ body: @escaping @MainActor () async -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let answer = FirstAnswer(continuation)
            Task { @MainActor in answer.give(await body()) }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                answer.give(nil)
            }
        }
    }

    /// A call on the stage that never ends (a promise that never settles and is kept, so it is not
    /// collected; a loop that never stops) is
    /// given up after `timeout`, and the stage draws the next formula: the timeout used to wait for the
    /// very call it was meant to abandon, so one hung render stopped every later diagram and formula.
    @Test func aHungCallTimesOutAndTheStageRecovers() async throws {
        let renderer = DiagramWebRenderer()
        renderer.timeout = .milliseconds(800)
        let warm = MathRequest(tex: "x^2", display: false, theme: .macOS, dark: false, fontSize: 13)
        #expect(await within(15) { await renderer.picture(for: warm) != nil } == true)
        for (index, script) in ["await new Promise(resolve => { window.stageHold = resolve })", "while (true) {}"].enumerated() {
            let start = ContinuousClock.now
            #expect(await within(5) { await renderer.finishesOnStage(script) } == false, "\(script)")
            #expect(ContinuousClock.now - start < .seconds(3), "\(script)")
            let next = MathRequest(tex: "y^\(index + 2)", display: false, theme: .macOS, dark: false, fontSize: 13)
            #expect(await within(15) { await renderer.picture(for: next) != nil } == true, "after \(script)")
        }
    }

    /// The stage needs no network: a diagram naming a web image (mermaid's image shape; front
    /// matter sends any flowchart to mermaid.js) must not reach the server, whatever the setting.
    /// mermaid.js ships with the app, the only place WebKit can run it, and not in UncialCore's resource
    /// bundle, which both extensions embed (PERF-11: 5.6 MB in each).
    @Test func mermaidShipsOnlyWithTheApp() throws {
        #expect(DiagramWebRenderer.libraryURL != nil)
        let coreBundle = try #require(Bundle.main.url(forResource: "UncialCore_UncialCore", withExtension: "bundle").flatMap(Bundle.init(url:)))
        #expect(coreBundle.url(forResource: "mermaid.min", withExtension: "js") == nil)
        #expect(coreBundle.url(forResource: "katex.min", withExtension: "js") != nil)
    }

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
        // The second time comes from the cache, same content. Quick Look's store gets what a saved file
        // holds, when told, not every version rendered while typing.
        #expect(await renderer.render([pieSource], theme: .github)[pieSource] == pie)
        #expect(store.diagrams(for: [pieSource, ganttSource], theme: .github).isEmpty)
        renderer.keepForQuickLook([pieSource, "nonsense diagram type"], theme: .github)
        #expect(store.diagrams(for: [pieSource, ganttSource], theme: .github).count == 1)
    }

    /// A source mermaid.js rejects is remembered like one it draws: every page render used to pay for it
    /// again (1.9 s for a 450-node fence). A render that is superseded before its turn on the stage does
    /// not run: typing left the page seconds behind while old versions rendered one by one.
    @Test func remembersFailuresAndSkipsSupersededRenders() async throws {
        let renderer = DiagramWebRenderer()
        let failing = "nonsense diagram type \(UUID())"
        _ = await renderer.render([failing], theme: .github)
        let afterFirst = renderer.stageRenders
        _ = await renderer.render([failing], theme: .github)
        #expect(renderer.stageRenders == afterFirst)

        let sources = (1...4).map { "gantt\n  dateFormat YYYY-MM-DD\n  section S\n  Task \($0) :a1, 2026-01-0\($0), 3d" }
        let before = renderer.stageRenders
        let superseded = Task { await renderer.render(sources, theme: .macOS) }
        superseded.cancel()
        _ = await superseded.value
        #expect(renderer.stageRenders - before <= 1, "\(renderer.stageRenders - before) renders ran for a cancelled page")
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

    /// beautiful-mermaid lays out a large flowchart for hundreds of milliseconds: off the main thread,
    /// so the editor keeps responding while a new diagram is drawn (it stalled 179 ms at 50 nodes, 444 ms
    /// at 100).
    @Test func laysOutDiagramsOffTheMainThread() async throws {
        let renderer = DiagramWebRenderer()
        _ = await renderer.image(for: DiagramRequest(source: "graph LR\n  A --> B", theme: .macOS, dark: false, scale: 1, width: 600))
        let run = UUID().uuidString.prefix(8)
        let edges = (0..<70).map { "  N\($0)[\"\(run) \($0)\"] --> N\($0 + 1)\n  N\($0) --> M\($0 % 9)" }.joined(separator: "\n")
        let request = DiagramRequest(source: "graph TD\n" + edges, theme: .macOS, dark: false, scale: 1, width: 600)
        var finished = false
        let drawing = Task { @MainActor in
            let image = await renderer.image(for: request)
            finished = true
            return image
        }
        let start = ContinuousClock.now
        var last = start
        var longest: Duration = .zero
        while !finished, ContinuousClock.now - start < .seconds(30) {
            try await Task.sleep(for: .milliseconds(5))
            let now = ContinuousClock.now
            longest = max(longest, now - last)
            last = now
        }
        #expect(await drawing.value != nil)
        // Other suites' main-actor tests run in between in a full run (up to about 0.3 s); the layout
        // itself stalled 0.8 s at 50 nodes and grows faster than the node count.
        #expect(longest < .milliseconds(600), "the main actor stalled \(longest)")
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
