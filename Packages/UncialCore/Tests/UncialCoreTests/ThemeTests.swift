import Foundation
import Testing
@testable import UncialCore

@Suite struct ThemeTests {
    /// The custom properties `css` declares.
    private func declaredProperties(in css: String) -> Set<String> {
        let declaration = try! NSRegularExpression(pattern: #"--[a-z0-9-]+(?=:)"#)
        let text = css as NSString
        return Set(declaration.matches(in: css, range: NSRange(location: 0, length: text.length)).map { text.substring(with: $0.range) })
    }

    /// The value `css` declares for `property` first (the light one), e.g. "2em" for `--h1-size`.
    private func value(of property: String, in css: String) -> String? {
        guard let start = css.range(of: property + ": ")?.upperBound, let end = css[start...].firstIndex(of: ";") else { return nil }
        return String(css[start..<end])
    }

    /// The raw values are stored in the settings and in the App Group's plist the extensions read.
    @Test func defaultIsMacOS() {
        #expect(Theme.default == .macOS)
        #expect(Theme(rawValue: "macos") == .macOS)
        #expect(Theme.allCases == [.macOS, .github, .solarized])
    }

    @Test(arguments: Theme.allCases)
    func everySheetHasTheBaseRulesLightAndDark(_ theme: Theme) {
        let css = Stylesheet.css(for: theme)
        #expect(css.contains(".markdown-body {"))
        #expect(css.contains("math { font-family:"))
        #expect(css.contains("color-scheme: light dark"))
        #expect(css.contains("@media (prefers-color-scheme: dark)"))
        #expect(css.contains("--bg:"))
        #expect(css.contains("--h1-border: 1px solid") && css.contains("--h2-border: 1px solid"))
        #expect(!css.contains("<script"))
    }

    /// Quick Look's window, not the app, answers `prefers-color-scheme`, so a sheet for the app's Light
    /// or Dark setting names that one scheme and has its dark rules applied or dropped; System keeps both.
    @Test(arguments: Theme.allCases)
    func sheetsFixedToLightOrDark(_ theme: Theme) {
        #expect(Stylesheet.css(for: theme, appearance: .system) == Stylesheet.css(for: theme))
        let dark = Stylesheet.css(for: theme, appearance: .dark)
        let light = Stylesheet.css(for: theme, appearance: .light)
        for css in [dark, light] {
            #expect(!css.contains("prefers-color-scheme") && !css.contains("color-scheme: light dark"))
            #expect(css.contains(".markdown-body {") && css.contains("--bg:"))
        }
        #expect(dark.contains("color-scheme: dark;") && light.contains("color-scheme: light;"))
        // A diagram shows its dark drawing on the dark page only.
        #expect(dark.contains("figure.mermaid .light { display: none; }") && !light.contains("figure.mermaid .light { display: none; }"))
    }

    /// The dark values come after the light ones, so they win; the light sheet has none of them.
    @Test func fixedDarkSheetsPutTheDarkValuesLast() throws {
        let dark = Stylesheet.css(for: .solarized, appearance: .dark)
        #expect(try #require(dark.range(of: "--bg: #002b36")).lowerBound > (try #require(dark.range(of: "--bg: #fdf6e3"))).lowerBound)
        #expect(!Stylesheet.css(for: .solarized, appearance: .light).contains("#002b36"))
    }

    /// The editor and the diagrams take the page's colors: a theme's palette is its sheet's `--bg`, `--fg`,
    /// `--accent` and `--muted`, light and dark. The macOS theme has none: it uses the system's colors.
    @Test(arguments: Theme.allCases)
    func editorPalettesMatchTheStylesheets(_ theme: Theme) {
        guard let palette = theme.editorPalette else {
            #expect(theme == .macOS)
            return
        }
        let css = Stylesheet.css(for: theme)
        for colors in [palette.light, palette.dark] {
            for (property, color) in [("bg", colors.background), ("fg", colors.foreground), ("accent", colors.accent), ("muted", colors.muted)] {
                let declaration = String(format: "--%@: #%06x", property, color)
                #expect(css.contains(declaration), "misses \(declaration)")
            }
        }
        let diagram = theme.diagramPalette
        #expect(diagram.light == DiagramPalette.Colors(background: palette.light.background, foreground: palette.light.foreground, accent: palette.light.accent, muted: palette.light.muted))
        #expect(diagram.dark == DiagramPalette.Colors(background: palette.dark.background, foreground: palette.dark.foreground, accent: palette.dark.accent, muted: palette.dark.muted))
    }

    @Test(arguments: Theme.allCases)
    func syntaxPalettesMatchTheStylesheets(_ theme: Theme) {
        let css = Stylesheet.css(for: theme)
        for scope in CodeHighlighter.Scope.allCases {
            for color in [theme.syntaxPalette.light.color(for: scope), theme.syntaxPalette.dark.color(for: scope)] {
                let declaration = String(format: "--code-%@: #%06x", scope.rawValue, color)
                #expect(css.contains(declaration), "misses \(declaration)")
            }
        }
    }

    @Test(arguments: Theme.allCases)
    func calloutPalettesMatchTheStylesheets(_ theme: Theme) {
        let css = Stylesheet.css(for: theme)
        #expect(css.contains(".callout { --callout-color: var(--callout-note);"))
        #expect(css.contains(".callout[data-callout=\"quote\"] { --callout-color: var(--callout-quote); }"))
        guard let palette = theme.calloutPalette else {
            // WebKit's system colors, and system teal's values for tip: WebKit has no teal keyword.
            #expect(theme == .macOS)
            #expect(css.contains("--callout-note: -apple-system-blue;") && css.contains("--callout-danger: -apple-system-red;"))
            #expect(css.contains("--callout-tip: #30b0c7;") && css.contains("--callout-tip: #40c8e0;"))
            return
        }
        for role in Callouts.Role.allCases {
            for color in [palette.light.color(for: role), palette.dark.color(for: role)] {
                let declaration = String(format: "--callout-%@: #%06x", role.rawValue, color)
                #expect(css.contains(declaration), "misses \(declaration)")
            }
        }
    }

    /// Live Preview sets text in the page's sizes: the body, line height and every heading level, whether
    /// the sheet gives a heading in pixels or in em of the body.
    @Test(arguments: Theme.allCases)
    func typographyMatchesTheStylesheets(_ theme: Theme) throws {
        let css = Stylesheet.css(for: theme)
        let type = theme.typography
        #expect(css.contains("--font-size: \(Int(type.bodySize))px;"))
        #expect(css.contains("--line-height: \(type.lineHeight);"))
        try #require(type.headingSizes.count == 6)
        for level in 1...6 {
            let size = try #require(value(of: "--h\(level)-size", in: css))
            let pixels = size.hasSuffix("em") ? Double(size.dropLast(2)).map { $0 * type.bodySize } : Double(size.dropLast(2))
            #expect(pixels.map { abs($0 - type.headingSizes[level - 1]) < 0.001 } == true, "h\(level) is \(size), the editor's \(type.headingSizes[level - 1])")
        }
        #expect(type.boldTopHeadings == css.contains("h1, h2 { font-weight: 700; }"))
    }

    /// Paper gets the page at full width with its backgrounds, code wrapped instead of clipped, and the
    /// blocks WebKit keeps whole, `.print-keep` among them (a heading and the block after it, `PDFExporter`).
    @Test(arguments: Theme.allCases, PageAppearance.allCases)
    func printRulesInEverySheet(_ theme: Theme, _ appearance: PageAppearance) {
        let css = Stylesheet.css(for: theme, appearance: appearance)
        #expect(css.contains("@media print {"))
        #expect(css.contains(".markdown-body { max-width: none; padding: 0; }"))
        #expect(css.contains("print-color-adjust: exact;"))
        #expect(css.contains("pre, table, figure, img, .callout, p.math, .print-keep { break-inside: avoid; }"))
        #expect(css.contains("pre, pre code { white-space: pre-wrap; overflow-wrap: anywhere; }"))
    }

    /// A page shown outside WebKit (an exported HTML file) cannot use WebKit's system colors: each becomes
    /// a variable the sheet declares, light and dark, and nothing else changes.
    @Test func systemColorsBecomeDeclaredVariables() {
        let names = Stylesheet.systemColorNames
        let colors = SystemColors(light: Dictionary(uniqueKeysWithValues: names.map { ($0, "#111111") }),
                                  dark: Dictionary(uniqueKeysWithValues: names.map { ($0, "#eeeeee") }))
        let original = Stylesheet.css(for: .macOS)
        let portable = Stylesheet.css(for: .macOS, systemColors: colors)
        #expect(!portable.contains("-apple-system-"))
        #expect(portable.contains("--font-body: -apple-system, system-ui"))
        for name in names {
            #expect(portable.contains("--system-\(name): #111111;") && portable.contains("--system-\(name): #eeeeee;"), "\(name)")
        }
        #expect(portable.contains("--bg: var(--system-text-background);"))
        #expect(portable.contains("--code-bg: color-mix(in srgb, var(--system-label) 6%, transparent);"))
        #expect(declaredProperties(in: portable).isSuperset(of: declaredProperties(in: original)))
        for theme in [Theme.github, .solarized] {
            #expect(Stylesheet.css(for: theme, systemColors: colors) == Stylesheet.css(for: theme))
        }
        // Fixed to light, the dark values go with the theme's other dark rules.
        let light = Stylesheet.css(for: .macOS, appearance: .light, systemColors: colors)
        #expect(light.contains("--system-label: #111111;") && !light.contains("#eeeeee"))
    }
}
