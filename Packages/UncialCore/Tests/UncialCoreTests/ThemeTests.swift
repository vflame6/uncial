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
}
