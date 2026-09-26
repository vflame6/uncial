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
    private var svgCache: [String: PreRenderedDiagram] = [:]
    private var imageCache: [DiagramRequest: NSImage] = [:]
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
    func render(_ sources: [String], theme: Theme) async -> [String: PreRenderedDiagram] {
        var result: [String: PreRenderedDiagram] = [:]
        for source in sources {
            if let diagram = await variants(for: source, theme: theme) {
                result[source] = diagram
            }
        }
        return result
    }

    private func variants(for source: String, theme: Theme) async -> PreRenderedDiagram? {
        let key = theme.rawValue + "\u{0}" + source
        if let cached = svgCache[key] { return cached }
        let diagram = await serialized { () -> PreRenderedDiagram? in
            guard let webView = await self.prepare(theme: theme) else { return nil }
            self.nextID += 1
            let id = self.nextID
            let palette = theme.diagramPalette
            guard let light = await self.svg(source, colors: palette.light, dark: false, id: "mermaid-light-\(id)", in: webView),
                  let dark = await self.svg(source, colors: palette.dark, dark: true, id: "mermaid-dark-\(id)", in: webView) else { return nil }
            return PreRenderedDiagram(light: light, dark: dark)
        }
        if let diagram {
            svgCache[key] = diagram
            store?.save([source: diagram], theme: theme)
        }
        return diagram
    }

    private func svg(_ source: String, colors: DiagramPalette.Colors, dark: Bool, id: String, in webView: WKWebView) async -> String? {
        let body = """
        mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: "base", darkMode: dark, themeVariables: variables,
                             fontFamily: "system-ui, -apple-system, sans-serif", flowchart: { htmlLabels: false }, logLevel: 5 });
        const result = await mermaid.render(id, text);
        return result.svg;
        """
        let arguments: [String: Any] = ["id": id, "text": source, "dark": dark, "variables": Self.themeVariables(colors)]
        let value = try? await withTimeout { try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: .page) }
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
        if let native = MermaidRenderer.nativeSVG(for: request.source) {
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
        if let image { imageCache[request] = image }
        return image
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
        _ = try? await webView.callAsyncJavaScript("document.getElementById('stage').innerHTML = '';", arguments: [:], in: nil, contentWorld: .page)
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
            await evaluate(library, in: webView)
            libraryLoaded = true
        }
        if stageTheme != theme {
            // The theme's stylesheet swaps in place; the library stays loaded.
            _ = try? await webView.callAsyncJavaScript("document.getElementById('theme').textContent = css;", arguments: ["css": Stylesheet.css(for: theme)], in: nil, contentWorld: .page)
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

    /// A process that cannot launch (the Quick Look sandbox) or dies ends the wait too.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageLoaded?.resume()
        pageLoaded = nil
        libraryLoaded = false
    }

    /// One diagram at a time on the stage.
    private func serialized<T>(_ body: @escaping @MainActor () async -> T) async -> T {
        let previous = last
        let task = Task { @MainActor () -> T in
            await previous.value
            return await body()
        }
        last = Task { _ = await task.value }
        return await task.value
    }

    private func withTimeout<T>(_ body: @escaping @MainActor () async throws -> T) async throws -> T {
        let limit = timeout
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { @MainActor in try await body() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw TimedOut()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }
}
