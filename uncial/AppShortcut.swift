import SwiftUI

/// Every keyboard shortcut the app offers, including the ones macOS provides. Menus bind the
/// custom ones from here; the Shortcuts settings tab lists all of them, so the two never drift.
enum AppShortcut: CaseIterable, Identifiable {
    case newDocument, open, save, close, closeAll
    case readOnly, livePreview, rawEditor, toggleEditorMode, reload
    case find
    case settings, quit

    var id: Self { self }

    var title: String {
        switch self {
        case .newDocument: "New…"
        case .open: "Open…"
        case .save: "Save"
        case .close: "Close"
        case .closeAll: "Close All"
        case .readOnly: "Read Only"
        case .livePreview: "Live Preview"
        case .rawEditor: "Raw Editor"
        case .toggleEditorMode: "Toggle Editor Mode"
        case .reload: "Reload"
        case .find: "Find in Source"
        case .settings: "Settings…"
        case .quit: "Quit Uncial"
        }
    }

    var section: String {
        switch self {
        case .newDocument, .open, .save, .close, .closeAll: "File"
        case .readOnly, .livePreview, .rawEditor, .toggleEditorMode, .reload: "View"
        case .find: "Edit"
        case .settings, .quit: "Uncial"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .newDocument: "n"
        case .open: "o"
        case .save: "s"
        case .close: "w"
        case .closeAll: "w"
        case .readOnly: "1"
        case .livePreview: "2"
        case .rawEditor: "3"
        case .toggleEditorMode: "e"
        case .reload: "r"
        case .find: "f"
        case .settings: ","
        case .quit: "q"
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .readOnly, .livePreview, .rawEditor: [.command, .option]
        case .toggleEditorMode: [.command, .shift]
        case .closeAll: [.command, .option]
        default: .command
        }
    }

    /// Menu-style rendering in the standard ⌃⌥⇧⌘ order, e.g. "⌥⌘1".
    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + String(key.character).uppercased()
    }

    /// Section titles in declaration order, without duplicates.
    static var sections: [String] {
        var seen: [String] = []
        for shortcut in allCases where !seen.contains(shortcut.section) {
            seen.append(shortcut.section)
        }
        return seen
    }

    static func shortcuts(in section: String) -> [AppShortcut] {
        allCases.filter { $0.section == section }
    }
}

extension View {
    func keyboardShortcut(_ shortcut: AppShortcut) -> some View {
        keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
    }
}
