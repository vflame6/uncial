import AppKit
import Testing
import UncialCore
import WebKit
@testable import Uncial

@MainActor
@Suite(.serialized) struct SystemColorResolverTests {
    @Test func coversEveryColorTheSheetsName() {
        #expect(Set(SystemColorResolver.colors.keys) == Set(Stylesheet.systemColorNames))
        let colors = SystemColorResolver.current()
        #expect(Set(colors.light.keys) == Set(Stylesheet.systemColorNames))
        #expect(Set(colors.dark.keys) == Set(Stylesheet.systemColorNames))
        #expect(colors.light["text-background"] == "rgb(255, 255, 255)")
        #expect(colors.dark["text-background"] == "rgb(30, 30, 30)")
        #expect(colors.light["label"]?.hasPrefix("rgba(0, 0, 0, ") == true)
        #expect(colors.dark["label"]?.hasPrefix("rgba(255, 255, 255, ") == true)
    }

    @Test func writesCSSColors() {
        #expect(SystemColorResolver.css(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)) == "rgb(255, 128, 0)")
        #expect(SystemColorResolver.css(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5)) == "rgba(0, 0, 0, 0.500)")
    }

    /// In WebKit the portable sheet looks like the native one: page, text and link colors match, light and dark.
    @Test func portablePageMatchesWebKitsColors() async throws {
        let body = "<p><a href=\"#x\">link</a></p>"
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let native = try await colors(of: HTMLDocument.wrap(body: body, title: "t", theme: .macOS), in: appearance)
            let portable = try await colors(of: HTMLDocument.wrap(body: body, title: "t", theme: .macOS, systemColors: SystemColorResolver.current()), in: appearance)
            #expect(!native.isEmpty && portable == native, "\(appearance.rawValue): \(native) vs \(portable)")
        }
    }

    /// The page's background, text and link colors in WebKit.
    private func colors(of html: String, in appearance: NSAppearance.Name) async throws -> String {
        try await withWebPage(html, appearance: appearance) { webView in
            try await webView.evaluateJavaScript("""
            [getComputedStyle(document.body).backgroundColor, getComputedStyle(document.body).color,
             getComputedStyle(document.querySelector('a')).color].join('|')
            """) as? String ?? ""
        }
    }
}
