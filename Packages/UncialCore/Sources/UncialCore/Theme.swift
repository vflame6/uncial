/// A document theme: one stylesheet with light and dark variants plus matching editor colors.
public enum Theme: String, CaseIterable, Identifiable, Sendable {
    case macOS = "macos"
    case github
    case solarized

    public static let `default`: Theme = .macOS

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .macOS: "macOS"
        case .github: "GitHub"
        case .solarized: "Solarized"
        }
    }

    /// Editor colors that match the rendered document. nil means the system text colors.
    public var editorPalette: EditorPalette? {
        switch self {
        case .macOS:
            nil
        case .github:
            EditorPalette(
                light: .init(background: 0xFFFFFF, foreground: 0x1F2328, accent: 0x0969DA, muted: 0x59636E, code: 0x953800),
                dark: .init(background: 0x0D1117, foreground: 0xF0F6FC, accent: 0x4493F8, muted: 0x9198A1, code: 0xFFA657)
            )
        case .solarized:
            EditorPalette(
                light: .init(background: 0xFDF6E3, foreground: 0x657B83, accent: 0x268BD2, muted: 0x93A1A1, code: 0x2AA198),
                dark: .init(background: 0x002B36, foreground: 0x839496, accent: 0x268BD2, muted: 0x586E75, code: 0x2AA198)
            )
        }
    }
}

extension Theme {
    /// Concrete colors for diagrams whose renderer bakes colors in (mermaid.js): the theme's page
    /// colors, with fixed stand-ins for the macOS theme's system colors.
    public var diagramPalette: DiagramPalette {
        switch self {
        case .macOS:
            return DiagramPalette(
                light: .init(background: 0xFFFFFF, foreground: 0x1D1D1F, accent: 0x007AFF, muted: 0x86868B),
                dark: .init(background: 0x1E1E1E, foreground: 0xF5F5F7, accent: 0x0A84FF, muted: 0x98989D)
            )
        case .github, .solarized:
            let palette = editorPalette!
            return DiagramPalette(
                light: .init(background: palette.light.background, foreground: palette.light.foreground, accent: palette.light.accent, muted: palette.light.muted),
                dark: .init(background: palette.dark.background, foreground: palette.dark.foreground, accent: palette.dark.accent, muted: palette.dark.muted)
            )
        }
    }
}

/// Colors as 0xRRGGBB for a renderer that cannot read CSS, one set per appearance.
public struct DiagramPalette: Equatable, Sendable {
    public struct Colors: Equatable, Sendable {
        public let background: UInt32
        public let foreground: UInt32
        public let accent: UInt32
        public let muted: UInt32

        public init(background: UInt32, foreground: UInt32, accent: UInt32, muted: UInt32) {
            self.background = background
            self.foreground = foreground
            self.accent = accent
            self.muted = muted
        }
    }

    public let light: Colors
    public let dark: Colors

    public init(light: Colors, dark: Colors) {
        self.light = light
        self.dark = dark
    }
}

/// Editor colors as 0xRRGGBB. Foundation-only so the Quick Look extension can link UncialCore.
public struct EditorPalette: Equatable, Sendable {
    /// Roles: `accent` for links, list markers and headings; `muted` for quotes, rules and URLs;
    /// `code` for inline and fenced code.
    public struct Colors: Equatable, Sendable {
        public let background: UInt32
        public let foreground: UInt32
        public let accent: UInt32
        public let muted: UInt32
        public let code: UInt32

        public init(background: UInt32, foreground: UInt32, accent: UInt32, muted: UInt32, code: UInt32) {
            self.background = background
            self.foreground = foreground
            self.accent = accent
            self.muted = muted
            self.code = code
        }
    }

    public let light: Colors
    public let dark: Colors

    public init(light: Colors, dark: Colors) {
        self.light = light
        self.dark = dark
    }
}
