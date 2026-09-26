import AppKit
import UncialCore

/// System / Light / Dark. Drives `NSApp.appearance`; rendered pages follow through `prefers-color-scheme`.
/// Quick Look gets it as `pageAppearance` and fixes its pages to it.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var pageAppearance: PageAppearance {
        switch self {
        case .system: .system
        case .light: .light
        case .dark: .dark
        }
    }

    /// nil means "follow the system".
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
