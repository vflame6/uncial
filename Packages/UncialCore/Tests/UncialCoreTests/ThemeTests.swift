import Testing
@testable import UncialCore

@Suite struct ThemeTests {
    @Test func defaultIsMacOS() {
        #expect(Theme.default == .macOS)
        #expect(Theme(rawValue: "macos") == .macOS)
        #expect(Theme.allCases == [.macOS, .github, .solarized])
    }

    @Test func titles() {
        #expect(Theme.allCases.map(\.title) == ["macOS", "GitHub", "Solarized"])
    }

    @Test func everyThemeHasBaseRulesLightAndDark() {
        for theme in Theme.allCases {
            let css = Stylesheet.css(for: theme)
            #expect(css.contains(".markdown-body {"), "\(theme) misses the base sheet")
            #expect(css.contains("color-scheme: light dark"), "\(theme) misses color-scheme")
            #expect(css.contains("@media (prefers-color-scheme: dark)"), "\(theme) misses a dark block")
            #expect(css.contains("--bg:"), "\(theme) misses variables")
            #expect(!css.contains("<script"))
        }
    }

    @Test func themeSignatures() {
        #expect(Stylesheet.css(for: .macOS).contains("-apple-system-label"))
        #expect(Stylesheet.css(for: .macOS).contains("-apple-system-text-background"))
        #expect(Stylesheet.css(for: .github).contains("#0d1117"))
        #expect(Stylesheet.css(for: .solarized).contains("#fdf6e3"))
        #expect(Stylesheet.css(for: .solarized).contains("#002b36"))
    }

    @Test func headingsGetDividersInEveryTheme() {
        for theme in Theme.allCases {
            let css = Stylesheet.css(for: theme)
            #expect(css.contains("--h1-border: 1px solid"), "\(theme) h1 has no divider")
            #expect(css.contains("--h2-border: 1px solid"), "\(theme) h2 has no divider")
        }
    }

    @Test func editorPalettes() {
        #expect(Theme.macOS.editorPalette == nil)
        #expect(Theme.github.editorPalette?.light.background == 0xFFFFFF)
        #expect(Theme.github.editorPalette?.dark.background == 0x0D1117)
        #expect(Theme.solarized.editorPalette?.light.background == 0xFDF6E3)
        #expect(Theme.solarized.editorPalette?.dark.foreground == 0x839496)
    }

    @Test func documentCarriesTheme() {
        let html = HTMLDocument.wrap(body: "<p>x</p>", title: "t", theme: .solarized)
        #expect(html.contains("<html data-theme=\"solarized\">"))
        #expect(html.contains("#fdf6e3"))
        #expect(HTMLDocument.wrap(body: "", title: "t").contains("data-theme=\"macos\""))
    }

    @Test func paletteRoles() {
        #expect(Theme.github.editorPalette?.light.code == 0x953800)
        #expect(Theme.github.editorPalette?.dark.accent == 0x4493F8)
        #expect(Theme.solarized.editorPalette?.light.muted == 0x93A1A1)
        #expect(Theme.solarized.editorPalette?.dark.code == 0x2AA198)
    }

    @Test func lineNumbersClassIsOptIn() {
        #expect(HTMLDocument.wrap(body: "", title: "t").contains("<html data-theme=\"macos\">"))
        #expect(HTMLDocument.wrap(body: "", title: "t", lineNumbers: true).contains("<html data-theme=\"macos\" class=\"line-numbers\">"))
    }

    @Test func syntaxPalettesMatchTheStylesheets() {
        for theme in Theme.allCases {
            let css = Stylesheet.css(for: theme)
            let palette = theme.syntaxPalette
            for scope in CodeHighlighter.Scope.allCases {
                let light = String(format: "--code-%@: #%06x", scope.rawValue, palette.light.color(for: scope))
                let dark = String(format: "--code-%@: #%06x", scope.rawValue, palette.dark.color(for: scope))
                #expect(css.contains(light), "\(theme) light misses \(light)")
                #expect(css.contains(dark), "\(theme) dark misses \(dark)")
            }
        }
        #expect(Theme.macOS.syntaxPalette.light.keyword == 0x9B2393)
        #expect(Theme.github.syntaxPalette.dark.string == 0xA5D6FF)
        #expect(Theme.solarized.syntaxPalette.light.comment == 0x93A1A1 && Theme.solarized.syntaxPalette.dark.comment == 0x586E75)
    }

    @Test func namesMathFonts() {
        for theme in Theme.allCases {
            #expect(Stylesheet.css(for: theme).contains("math { font-family:"), "\(theme) has no math font rule")
        }
    }
}
