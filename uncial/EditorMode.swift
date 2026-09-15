/// How the source editor shows Markdown: as plain source, or rendered in place with the syntax
/// of the caret's line revealed.
enum EditorPresentation: Equatable {
    case source, inline
}

/// What a document window shows: the rendered page, the source rendered in place, source and
/// page side by side, or the plain source.
enum EditorMode: String, CaseIterable, Identifiable {
    case readOnly
    /// Obsidian-style: one editor, markers hidden except on the caret's line. Stored as
    /// `inlinePreview` because `livePreview` was the split's stored value before 2026-09-15.
    case livePreview = "inlinePreview"
    case split
    case rawEditor

    /// The value stored for what is now `split` before 2026-09-15; `AppSettings` migrates it.
    static let legacySplitRawValue = "livePreview"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readOnly: "Read Only"
        case .livePreview: "Live Preview"
        case .split: "Split View"
        case .rawEditor: "Raw Editor"
        }
    }

    var summary: String {
        switch self {
        case .readOnly: "Rendered document only."
        case .livePreview: "Markdown rendered in place; the line with the cursor shows its source."
        case .split: "Markdown source beside the rendered document, updating as you type."
        case .rawEditor: "Markdown source only."
        }
    }

    var systemImage: String {
        switch self {
        case .readOnly: "doc.richtext"
        case .livePreview: "pencil.line"
        case .split: "rectangle.split.2x1"
        case .rawEditor: "chevron.left.forwardslash.chevron.right"
        }
    }

    var showsEditor: Bool { self != .readOnly }
    var showsPreview: Bool { self == .readOnly || self == .split }
    var presentation: EditorPresentation { self == .livePreview ? .inline : .source }

    /// Read Only → Live Preview → Split View → Raw Editor → Read Only.
    var next: EditorMode {
        switch self {
        case .readOnly: .livePreview
        case .livePreview: .split
        case .split: .rawEditor
        case .rawEditor: .readOnly
        }
    }

    var shortcut: AppShortcut {
        switch self {
        case .readOnly: .readOnly
        case .livePreview: .livePreview
        case .split: .splitView
        case .rawEditor: .rawEditor
        }
    }
}
