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
    /// Colors for highlighted code, the same values the theme's stylesheet sets as `--code-…`
    /// variables: Xcode's for the macOS theme, Primer's for GitHub, the Solarized accents.
    public var syntaxPalette: SyntaxPalette {
        switch self {
        case .macOS:
            SyntaxPalette(
                light: .init(comment: 0x5D6C79, keyword: 0x9B2393, string: 0xC41A16, number: 0x1C00CF, type: 0x3E8087, function: 0x4B21B0,
                             variable: 0x0F68A0, meta: 0x643820, tag: 0x0B4F79, addition: 0x1A7F37, deletion: 0xCF222E),
                dark: .init(comment: 0x6C7986, keyword: 0xFC5FA3, string: 0xFC6A5D, number: 0xD0BF69, type: 0x5DD8FF, function: 0xA167E6,
                            variable: 0x67B7A4, meta: 0xFD8F3F, tag: 0x41A1C0, addition: 0x3FB950, deletion: 0xF85149)
            )
        case .github:
            SyntaxPalette(
                light: .init(comment: 0x59636E, keyword: 0xCF222E, string: 0x0A3069, number: 0x0550AE, type: 0x0550AE, function: 0x8250DF,
                             variable: 0x953800, meta: 0x0550AE, tag: 0x116329, addition: 0x116329, deletion: 0x82071E),
                dark: .init(comment: 0x9198A1, keyword: 0xFF7B72, string: 0xA5D6FF, number: 0x79C0FF, type: 0x79C0FF, function: 0xD2A8FF,
                            variable: 0xFFA657, meta: 0x79C0FF, tag: 0x7EE787, addition: 0x3FB950, deletion: 0xF85149)
            )
        case .solarized:
            SyntaxPalette(
                light: .init(comment: 0x93A1A1, keyword: 0x859900, string: 0x2AA198, number: 0xD33682, type: 0xB58900, function: 0x268BD2,
                             variable: 0x6C71C4, meta: 0xCB4B16, tag: 0x268BD2, addition: 0x859900, deletion: 0xDC322F),
                dark: .init(comment: 0x586E75, keyword: 0x859900, string: 0x2AA198, number: 0xD33682, type: 0xB58900, function: 0x268BD2,
                            variable: 0x6C71C4, meta: 0xCB4B16, tag: 0x268BD2, addition: 0x859900, deletion: 0xDC322F)
            )
        }
    }

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

/// Colors for highlighted code as 0xRRGGBB, one set per appearance, one per `CodeHighlighter.Scope`.
public struct SyntaxPalette: Equatable, Sendable {
    public struct Colors: Equatable, Sendable {
        public let comment: UInt32
        public let keyword: UInt32
        public let string: UInt32
        public let number: UInt32
        public let type: UInt32
        public let function: UInt32
        public let variable: UInt32
        public let meta: UInt32
        public let tag: UInt32
        public let addition: UInt32
        public let deletion: UInt32

        public init(comment: UInt32, keyword: UInt32, string: UInt32, number: UInt32, type: UInt32, function: UInt32,
                    variable: UInt32, meta: UInt32, tag: UInt32, addition: UInt32, deletion: UInt32) {
            self.comment = comment
            self.keyword = keyword
            self.string = string
            self.number = number
            self.type = type
            self.function = function
            self.variable = variable
            self.meta = meta
            self.tag = tag
            self.addition = addition
            self.deletion = deletion
        }

        public func color(for scope: CodeHighlighter.Scope) -> UInt32 {
            switch scope {
            case .comment: comment
            case .keyword: keyword
            case .string: string
            case .number: number
            case .type: type
            case .function: function
            case .variable: variable
            case .meta: meta
            case .tag: tag
            case .addition: addition
            case .deletion: deletion
            }
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
