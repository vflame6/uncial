/// Concrete values for the WebKit-only `-apple-system-*` colors a theme names, keyed by the name after
/// `-apple-system-` (`label`, `text-background`, …), as CSS colors for the light and the dark appearance.
/// A page that leaves the app (an exported HTML file) carries them, since other browsers know none of
/// WebKit's system colors; the app resolves them from the `NSColor`s WebKit uses (`SystemColorResolver`).
public struct SystemColors: Equatable, Sendable {
    public var light: [String: String]
    public var dark: [String: String]

    public init(light: [String: String], dark: [String: String]) {
        self.light = light
        self.dark = dark
    }
}
