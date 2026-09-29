import Foundation
import UncialCore
import UniformTypeIdentifiers

/// What File ▸ Export… writes: a paginated PDF or a standalone HTML page.
enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf, html

    var id: Self { self }

    var title: String {
        switch self {
        case .pdf: "PDF"
        case .html: "HTML"
        }
    }

    var fileExtension: String { rawValue }

    var contentType: UTType {
        switch self {
        case .pdf: .pdf
        case .html: .html
        }
    }

    /// `name` with this format's extension: a Markdown one (`note.md`) or another format's
    /// (`note.html`) is replaced, any other kept (`v1.2` → `v1.2.pdf`); `Untitled` when nothing is left.
    func fileName(for name: String) -> String {
        let known = MarkdownText.fileExtensions.union(Self.allCases.map(\.fileExtension))
        let base = known.contains((name as NSString).pathExtension.lowercased()) ? (name as NSString).deletingPathExtension : name
        return (base.isEmpty ? "Untitled" : base) + "." + fileExtension
    }
}
