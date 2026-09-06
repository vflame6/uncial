/// What a document window shows: the rendered page, the Markdown source, or both side by side.
enum EditorMode: String, CaseIterable, Identifiable {
    case readOnly, livePreview, rawEditor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readOnly: "Read Only"
        case .livePreview: "Live Preview"
        case .rawEditor: "Raw Editor"
        }
    }

    var summary: String {
        switch self {
        case .readOnly: "Rendered document only."
        case .livePreview: "Markdown source beside the rendered document, updating as you type."
        case .rawEditor: "Markdown source only."
        }
    }

    var systemImage: String {
        switch self {
        case .readOnly: "doc.richtext"
        case .livePreview: "rectangle.split.2x1"
        case .rawEditor: "chevron.left.forwardslash.chevron.right"
        }
    }

    var showsEditor: Bool { self != .readOnly }
    var showsPreview: Bool { self != .rawEditor }

    /// Read Only → Live Preview → Raw Editor → Read Only.
    var next: EditorMode {
        switch self {
        case .readOnly: .livePreview
        case .livePreview: .rawEditor
        case .rawEditor: .readOnly
        }
    }

    var shortcut: AppShortcut {
        switch self {
        case .readOnly: .readOnly
        case .livePreview: .livePreview
        case .rawEditor: .rawEditor
        }
    }
}
