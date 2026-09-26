import AppKit
import UncialCore
import WebKit

/// One diagram as Live Preview wants it: a bitmap in the editor's current look.
nonisolated struct DiagramRequest: Hashable {
    /// The fence text, as `MermaidRenderer.key(for:)` normalizes it.
    let source: String
    let theme: Theme
    let dark: Bool
    /// The editor's text scale; the bitmap's point size grows with it.
    let scale: CGFloat
    /// The room the editor has for the picture in points; diagrams that size to their container
    /// (mermaid.js gives them `width="100%"`) fill this before scaling.
    let width: CGFloat
}

/// One formula as Live Preview wants it: KaTeX's MathML drawn by WebKit at the editor's size.
nonisolated struct MathRequest: Hashable {
    let tex: String
    let display: Bool
    let theme: Theme
    let dark: Bool
    /// The editor's body size in points, the formula's font size.
    let fontSize: CGFloat
}

/// The official mermaid.js in a hidden web view, one per process and created on first use. It draws
/// the diagram types beautiful-mermaid lacks to SVG in the theme's light and dark colors for the
/// rendered page, and draws any diagram, and any formula (KaTeX's MathML, which needs a layout
/// engine to become pixels), to a bitmap for Live Preview. The page is a blank document carrying the
/// theme's stylesheet, with no access to files or the network, and mermaid runs with
/// `securityLevel: "strict"`; the document page itself still gets no script. Everything drawn for
/// the page also lands in `store` for the Quick Look extension, where WebKit cannot launch its
/// helper processes (probed 2026-09-16: "web process failed to launch").
@MainActor
final class DiagramWebRenderer: NSObject, WKNavigationDelegate {
    static let shared = DiagramWebRenderer()

    private var webView: WKWebView?
    private var window: NSWindow?
    private var pageLoaded: CheckedContinuation<Void, Never>?
    private var libraryLoaded = false
    private var stageTheme: Theme?
    /// What mermaid.js made of a source per theme, rejections included (nil), so a failing fence is not
    /// drawn again on every page render (PERF-7); the oldest go beyond `svgCacheLimit` entries.
    private var svgCache: [String: PreRenderedDiagram?] = [:]
    private var svgCacheOrder: [String] = []
    static let svgCacheLimit = 256
    /// How many sources went to mermaid.js on the stage, for tests.
    private(set) var stageRenders = 0
    /// Bitmaps drawn for Live Preview, oldest first out once they hold more than `imageCacheLimit`
    /// bytes of pixels (WebKit's snapshots keep their pixels resident in its helper process).
    private var imageCache: [DiagramRequest: NSImage] = [:]
    private var imageCacheOrder: [DiagramRequest] = []
    private var imageCacheBytes = 0
    static let imageCacheLimit = 128 * 1024 * 1024
    private var mathCache: [MathRequest: MathPicture] = [:]
    private var nextID = 0
    private var last: Task<Void, Never> = Task {}
    /// How long one diagram may take before it counts as failed.
    var timeout: Duration = .seconds(20)
    /// Where the page's diagrams are kept for Quick Look; the app sets it at launch.
    var store: DiagramStore?

    private struct TimedOut: Error {}

    // MARK: SVG for the page

    /// Light and dark SVG for every source mermaid.js accepts, keyed by source; the rest are left out.
    /// A cancelled caller (a page render superseded by typing) gets what is done and starts nothing more.
    func render(_ sources: [String], theme: Theme) async -> [String: PreRenderedDiagram] {
        var result: [String: PreRenderedDiagram] = [:]
        for source in sources {
            guard !Task.isCancelled else { break }
            if let diagram = await variants(for: source, theme: theme) {
                result[source] = diagram
            }
        }
        return result
    }

    /// Hands Quick Look's store the diagrams of `sources` drawn so far: the app calls it with what the
    /// saved file holds, since Quick Look previews the file on disk (BUG-20: every version typed went
    /// into the 400-file store and pushed out other documents' diagrams).
    func keepForQuickLook(_ sources: [String], theme: Theme) {
        guard let store else { return }
        var diagrams: [String: PreRenderedDiagram] = [:]
        for source in sources {
            if let diagram = svgCache[theme.rawValue + "\u{0}" + source] ?? nil { diagrams[source] = diagram }
        }
        if !diagrams.isEmpty { store.save(diagrams, theme: theme) }
    }

    private func variants(for source: String, theme: Theme) async -> PreRenderedDiagram? {
        let key = theme.rawValue + "\u{0}" + source
        if let cached = svgCache[key] { return cached }
        guard !Task.isCancelled else { return nil }
        // nil: nothing to remember (superseded, the stage unavailable or timed out); .some(nil): mermaid.js
        // rejected the source.
        let outcome = await serialized { () -> PreRenderedDiagram?? in
            // Another request may have drawn it while this one waited.
            if let cached = self.svgCache[key] { return cached }
            guard !Task.isCancelled, let webView = await self.prepare(theme: theme) else { return nil }
            self.stageRenders += 1
            self.nextID += 1
            let id = self.nextID
            let palette = theme.diagramPalette
            do {
                guard let light = try await self.svg(source, colors: palette.light, dark: false, id: "mermaid-light-\(id)", in: webView),
                      let dark = try await self.svg(source, colors: palette.dark, dark: true, id: "mermaid-dark-\(id)", in: webView) else {
                    return .some(nil)
                }
                return .some(PreRenderedDiagram(light: light, dark: dark))
            } catch {
                return nil
            }
        }
        guard let outcome else { return nil }
        remember(outcome, for: key)
        return outcome
    }

    private func remember(_ diagram: PreRenderedDiagram?, for key: String) {
        if svgCache.updateValue(diagram, forKey: key) == nil {
            svgCacheOrder.append(key)
        }
        while svgCacheOrder.count > Self.svgCacheLimit {
            svgCache.removeValue(forKey: svgCacheOrder.removeFirst())
        }
    }

    /// The SVG, or nil when mermaid.js rejects the source; throws `TimedOut` when the stage ran out of
    /// time, which says nothing about the source.
    private func svg(_ source: String, colors: DiagramPalette.Colors, dark: Bool, id: String, in webView: WKWebView) async throws -> String? {
        let body = """
        mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: "base", darkMode: dark, themeVariables: variables,
                             fontFamily: "system-ui, -apple-system, sans-serif", flowchart: { htmlLabels: false }, logLevel: 5 });
        const result = await mermaid.render(id, text);
        return result.svg;
        """
        let arguments: [String: Any] = ["id": id, "text": source, "dark": dark, "variables": Self.themeVariables(colors)]
        let value: Any?
        do {
            value = try await withTimeout { try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page) }
        } catch let error as TimedOut {
            throw error
        } catch {
            return nil
        }
        guard let svg = value as? String, svg.hasPrefix("<svg") else { return nil }
        return svg
    }

    /// mermaid's `base` theme derives the rest from these.
    static func themeVariables(_ colors: DiagramPalette.Colors) -> [String: String] {
        let background = hex(colors.background)
        let foreground = hex(colors.foreground)
        let accent = hex(colors.accent)
        let muted = hex(colors.muted)
        let primary = hex(mix(colors.accent, into: colors.background, 0.16))
        let secondary = hex(mix(colors.accent, into: colors.background, 0.08))
        let tertiary = hex(mix(colors.foreground, into: colors.background, 0.06))
        return [
            "background": background, "textColor": foreground, "titleColor": foreground, "lineColor": muted,
            "primaryColor": primary, "primaryTextColor": foreground, "primaryBorderColor": accent,
            "secondaryColor": secondary, "secondaryTextColor": foreground, "secondaryBorderColor": muted,
            "tertiaryColor": tertiary, "tertiaryTextColor": foreground, "tertiaryBorderColor": muted,
            "mainBkg": primary, "nodeBorder": accent, "clusterBkg": tertiary, "clusterBorder": muted,
            "edgeLabelBackground": background, "noteBkgColor": tertiary, "noteTextColor": foreground, "noteBorderColor": muted,
            "pieTitleTextColor": foreground, "pieSectionTextColor": foreground, "pieLegendTextColor": foreground,
            "pieStrokeColor": background, "pieOuterStrokeColor": muted,
            "sectionBkgColor": tertiary, "altSectionBkgColor": background, "sectionBkgColor2": secondary,
            "taskBkgColor": primary, "taskBorderColor": accent, "taskTextColor": foreground, "taskTextLightColor": foreground,
            "taskTextDarkColor": foreground, "taskTextOutsideColor": foreground, "taskTextClickableColor": accent,
            "activeTaskBkgColor": secondary, "activeTaskBorderColor": accent, "doneTaskBkgColor": tertiary, "doneTaskBorderColor": muted,
            "gridColor": muted, "todayLineColor": accent, "labelColor": foreground, "altBackground": tertiary,
            "fontSize": "15px",
        ]
    }

    static func hex(_ rgb: UInt32) -> String {
        String(format: "#%06X", rgb & 0xFFFFFF)
    }

    /// `amount` of `color` blended into `base`, per channel.
    static func mix(_ color: UInt32, into base: UInt32, _ amount: Double) -> UInt32 {
        var result: UInt32 = 0
        for shift in [16, 8, 0] as [UInt32] {
            let top = Double((color >> shift) & 0xFF)
            let bottom = Double((base >> shift) & 0xFF)
            let channel = UInt32((bottom + (top - bottom) * amount).rounded()) & 0xFF
            result |= channel << shift
        }
        return result
    }

    // MARK: Bitmaps for Live Preview

    /// The diagram drawn at its natural size times `request.scale`, with 2× pixels; nil when no
    /// engine accepts it.
    func image(for request: DiagramRequest) async -> NSImage? {
        if let cached = imageCache[request] { return cached }
        let svg: String
        // beautiful-mermaid's layout takes hundreds of milliseconds for a large diagram (PERF-8): off the
        // main actor; MermaidRenderer is thread-safe.
        let source = request.source
        if let native = await Task.detached(priority: .userInitiated, operation: { MermaidRenderer.nativeSVG(for: source) }).value {
            svg = native
        } else if let diagram = await variants(for: request.source, theme: request.theme) {
            svg = request.dark ? diagram.dark : diagram.light
        } else {
            return nil
        }
        let image = await serialized { () -> NSImage? in
            guard let webView = await self.prepare(theme: request.theme) else { return nil }
            self.ensureWindow(around: webView)
            webView.appearance = NSAppearance(named: request.dark ? .darkAqua : .aqua)
            let measure = """
            const stage = document.getElementById("stage");
            stage.style.width = width + "px";
            stage.style.fontSize = "";
            stage.style.padding = "";
            stage.innerHTML = svg;
            await new Promise(resolve => setTimeout(resolve, 30));
            const box = stage.querySelector("svg").getBoundingClientRect();
            return [box.left + window.scrollX, box.top + window.scrollY, box.width, box.height];
            """
            let width = max(120, min(request.width, 4000)).rounded()
            guard let box = try? await self.withTimeout({ try await webView.callAsyncJavaScript(measure, arguments: ["svg": svg, "width": width], in: nil, contentWorld: .page) }) as? [Double],
                  box.count == 4, box[2] > 0, box[3] > 0 else { return nil }
            let rect = CGRect(x: box[0], y: box[1], width: box[2].rounded(.up), height: box[3].rounded(.up))
            return await self.snapshot(of: rect, pixelsPerPoint: 2 * request.scale, pointSize: NSSize(width: rect.width * request.scale, height: rect.height * request.scale), in: webView)
        }
        if let image { cache(image, for: request) }
        return image
    }

    private func cache(_ image: NSImage, for request: DiagramRequest) {
        guard imageCache.updateValue(image, forKey: request) == nil else { return }
        imageCacheOrder.append(request)
        imageCacheBytes += Self.bytes(of: image)
        while imageCacheBytes > Self.imageCacheLimit, imageCacheOrder.count > 1 {
            let oldest = imageCacheOrder.removeFirst()
            if let evicted = imageCache.removeValue(forKey: oldest) {
                imageCacheBytes -= Self.bytes(of: evicted)
            }
        }
    }

    private static func bytes(of image: NSImage) -> Int {
        image.representations.map { $0.pixelsWide * $0.pixelsHigh * 4 }.max() ?? 0
    }

    /// The formula at `request.fontSize` in the page's text color, with 2× pixels and its baseline;
    /// nil when the stage is unavailable. Bad TeX draws as KaTeX's red source, like on the page.
    func picture(for request: MathRequest) async -> MathPicture? {
        if let cached = mathCache[request] { return cached }
        let html = MathRenderer.mathML(request.tex, display: request.display)
        let picture = await serialized { () -> MathPicture? in
            guard let webView = await self.prepare(theme: request.theme) else { return nil }
            self.ensureWindow(around: webView)
            webView.appearance = NSAppearance(named: request.dark ? .darkAqua : .aqua)
            // The marker, an empty inline block, sits on the baseline of the formula's line.
            let measure = """
            const stage = document.getElementById("stage");
            stage.style.width = "max-content";
            stage.style.fontSize = size + "px";
            stage.style.padding = "4px";
            stage.innerHTML = html + '<span id="stage-baseline" style="display: inline-block; width: 0; height: 0"></span>';
            await new Promise(resolve => setTimeout(resolve, 30));
            const box = (stage.querySelector("math") || stage.firstElementChild).getBoundingClientRect();
            const marker = document.getElementById("stage-baseline").getBoundingClientRect();
            return [box.left + window.scrollX, box.top + window.scrollY, box.width, box.height, marker.top + window.scrollY];
            """
            guard let box = try? await self.withTimeout({ try await webView.callAsyncJavaScript(measure, arguments: ["html": html, "size": Double(request.fontSize)], in: nil, contentWorld: .page) }) as? [Double],
                  box.count == 5, box[2] > 0, box[3] > 0 else { return nil }
            // One pixel around the box for ink that overhangs it.
            let rect = CGRect(x: floor(box[0]) - 1, y: floor(box[1]) - 1, width: ceil(box[0] + box[2]) - floor(box[0]) + 2, height: ceil(box[1] + box[3]) - floor(box[1]) + 2)
            let baseline = min(max((box[4] - rect.minY).rounded(), 0), rect.height)
            guard let snapshot = await self.snapshot(of: rect, pixelsPerPoint: 2, pointSize: rect.size, in: webView) else { return nil }
            return MathPicture(image: snapshot, size: rect.size, baseline: baseline)
        }
        if let picture { mathCache[request] = picture }
        return picture
    }

    /// The page area `rect` at `pixelsPerPoint`, sized `pointSize`; the viewport grows to cover it
    /// first (the snapshot covers the viewport only), and the stage is cleared after.
    private func snapshot(of rect: CGRect, pixelsPerPoint: CGFloat, pointSize: NSSize, in webView: WKWebView) async -> NSImage? {
        if rect.maxX > webView.frame.width || rect.maxY > webView.frame.height {
            let size = NSSize(width: max(webView.frame.width, rect.maxX + 40), height: max(webView.frame.height, rect.maxY + 40))
            window?.setContentSize(size)
            webView.frame = NSRect(origin: .zero, size: size)
            try? await Task.sleep(for: .milliseconds(50))
        }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        configuration.snapshotWidth = NSNumber(value: Double(rect.width * pixelsPerPoint))
        guard let snapshot = try? await withTimeout({ try await webView.takeSnapshot(configuration: configuration) }) else { return nil }
        snapshot.size = pointSize
        _ = try? await withTimeout { try await webView.callAsyncJavaScript("document.getElementById('stage').innerHTML = '';", arguments: [:], in: nil, contentWorld: .page) }
        return snapshot
    }

    /// Snapshots need the view in a window; it is never shown.
    private func ensureWindow(around webView: WKWebView) {
        guard window == nil else { return }
        let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        self.window = window
    }

    // MARK: The stage

    /// The web view with the page for `theme` loaded and mermaid.js evaluated, or nil when the
    /// library is missing.
    private func prepare(theme: Theme) async -> WKWebView? {
        let webView: WKWebView
        if let existing = self.webView {
            webView = existing
        } else {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            // mermaid.js comes in as a string and the page needs nothing from the web: whatever a
            // diagram names (an image shape's URL) is not fetched, whether remote content is on or off.
            if let rules = await RemoteContentBlocker.shared.ruleList() {
                configuration.userContentController.add(rules)
            }
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
            // Transparent snapshots, so a picture shows the editor's selection through (the page's own
            // background is transparent too).
            view.setValue(false, forKey: "drawsBackground")
            view.navigationDelegate = self
            self.webView = view
            webView = view
        }
        if !libraryLoaded {
            guard let url = MermaidRenderer.webLibraryURL, let library = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let loaded = try? await withTimeout { () -> Bool in
                await withCheckedContinuation { continuation in
                    self.pageLoaded = continuation
                    webView.loadHTMLString(Self.page(theme: theme), baseURL: nil)
                }
                return true
            }
            pageLoaded = nil
            guard loaded == true else { return nil }
            stageTheme = theme
            guard (try? await withTimeout({ () -> Bool in
                await self.evaluate(library, in: webView)
                return true
            })) == true else { return nil }
            libraryLoaded = true
        }
        if stageTheme != theme {
            // The theme's stylesheet swaps in place; the library stays loaded.
            // `try?` flattens the script's own nil result: say `true` for a call that finished.
            guard (try? await withTimeout({ () -> Bool in
                _ = try await webView.callAsyncJavaScript("document.getElementById('theme').textContent = css;", arguments: ["css": Stylesheet.css(for: theme)], in: nil, contentWorld: .page)
                return true
            })) == true else { return nil }
            stageTheme = theme
        }
        return webView
    }

    /// The document page with only an empty figure, which keeps its natural size and no padding.
    static func page(theme: Theme) -> String {
        let overrides = """
        <style id="stage-style">
        html, body { background: transparent; }
        .markdown-body { max-width: none; padding: 0; margin: 0; }
        figure.mermaid { margin: 0; text-align: left; }
        figure.mermaid svg { display: block; }
        </style>
        </head>
        """
        return HTMLDocument.wrap(body: "<figure class=\"mermaid\" id=\"stage\"></figure>", title: "diagrams", theme: theme)
            .replacingOccurrences(of: "<style>", with: "<style id=\"theme\">")
            .replacingOccurrences(of: "</head>", with: overrides)
    }

    /// The callback form: the async `evaluateJavaScript` traps when a script yields `undefined`.
    private func evaluate(_ script: String, in webView: WKWebView) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            webView.evaluateJavaScript(script) { _, _ in continuation.resume() }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded?.resume()
        pageLoaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pageLoaded?.resume()
        pageLoaded = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        pageLoaded?.resume()
        pageLoaded = nil
    }

    /// A process that cannot launch (the Quick Look sandbox) or dies ends the wait too.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageLoaded?.resume()
        pageLoaded = nil
        libraryLoaded = false
    }

    /// Whether `script` runs to its end on the stage the way a render's calls do: one at a time, and
    /// given up after `timeout`. For tests.
    func finishesOnStage(_ script: String) async -> Bool {
        await serialized {
            guard let webView = await self.prepare(theme: .default) else { return false }
            return (try? await self.withTimeout { () -> Bool in
                _ = try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
                return true
            }) == true
        }
    }

    /// One diagram at a time on the stage. A caller's cancellation reaches the body, which checks it
    /// once its turn comes.
    private func serialized<T>(_ body: @escaping @MainActor () async -> T) async -> T {
        let previous = last
        let task = Task { @MainActor () -> T in
            await previous.value
            return await body()
        }
        last = Task { _ = await task.value }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// `body`'s result, or `TimedOut` once `timeout` has passed, whichever comes first. WebKit's calls
    /// ignore cancellation, so the body is left to finish on its own, and a timeout takes the stage down
    /// with it (STAB-3, 2026-09-26: a task group waited for the very call it was meant to abandon, so one
    /// hung render stopped every later diagram and formula).
    private func withTimeout<T>(_ body: @escaping @MainActor () async throws -> T) async throws -> T {
        let limit = timeout
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<T, Error>, Never>) in
            let outcome = FirstOutcome(continuation)
            let timer = Task { @MainActor in
                do {
                    try await Task.sleep(for: limit)
                    outcome.settle(.failure(TimedOut()))
                } catch {}
            }
            Task { @MainActor in
                do {
                    outcome.settle(.success(try await body()))
                } catch {
                    outcome.settle(.failure(error))
                }
                timer.cancel()
            }
        }
        if case .failure(let error) = result, error is TimedOut {
            resetStage()
        }
        return try result.get()
    }

    /// After a timeout the page may still be busy with the call that ran out of time (a promise that
    /// never settles, a loop that never ends; JavaScript cannot be interrupted): the stage goes, its
    /// process killed, and the next request builds a new one. Without the process identifier (private,
    /// so checked first) the page is replaced, which ends a wait but not a loop.
    private func resetStage() {
        pageLoaded?.resume()
        pageLoaded = nil
        libraryLoaded = false
        stageTheme = nil
        guard let webView else { return }
        webView.navigationDelegate = nil
        let identifier = NSSelectorFromString("_webProcessIdentifier")
        if webView.responds(to: identifier), let process = webView.value(forKey: "_webProcessIdentifier") as? Int32, process > 0 {
            kill(process, SIGKILL)
        } else {
            webView.loadHTMLString("", baseURL: nil)
        }
        window?.contentView = nil
        window = nil
        self.webView = nil
    }
}

/// The first outcome of a race between a stage call and its timer; the later one is dropped.
@MainActor private final class FirstOutcome<T> {
    private var continuation: CheckedContinuation<Result<T, Error>, Never>?

    init(_ continuation: CheckedContinuation<Result<T, Error>, Never>) {
        self.continuation = continuation
    }

    func settle(_ result: Result<T, Error>) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
