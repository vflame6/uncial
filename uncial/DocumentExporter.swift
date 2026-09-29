import AppKit
import UncialCore

/// What File ▸ Export… renders: the document as its window has it, unsaved edits included.
nonisolated struct ExportSnapshot: Sendable {
    let text: String
    /// The document's file: relative pictures resolve against it and the export is named after it.
    let fileURL: URL?
    let theme: Theme
    let remoteContent: Bool
    let attachments: AttachmentSearch

    /// The document's file name, where the export panel's name starts.
    var fileName: String { fileURL?.lastPathComponent ?? "Untitled.md" }
    /// The exported page's title: the file name without its extension.
    var title: String { (fileName as NSString).deletingPathExtension }
}

extension ExportSnapshot {
    @MainActor init(model: DocumentViewModel) {
        self.init(text: model.text, fileURL: model.fileURL, theme: model.theme, remoteContent: model.remoteContent, attachments: model.attachmentSearch)
    }
}

/// File ▸ Export… for one document window: the save panel with its Format popup, then the file, one
/// export at a time. A failure shows as an alert on the window.
@Observable
final class DocumentExporter {
    /// The panel is open or a file is being written; the menu item waits.
    private(set) var isRunning = false
    /// Tells the user an export failed (an alert sheet); tests listen here instead.
    @ObservationIgnored var reportError: @MainActor (Error, NSWindow?) -> Void = { error, window in
        DocumentExporter.showAlert(error, window)
    }

    /// Asks where and in which format (the one chosen last comes first), then exports.
    func run(_ snapshot: ExportSnapshot, settings: AppSettings, window: NSWindow?) {
        guard !isRunning else { return }
        isRunning = true
        let export = ExportPanel(format: settings.exportFormat, documentName: snapshot.fileName, directory: snapshot.fileURL?.deletingLastPathComponent())
        export.begin(on: window) { [self] choice in
            guard let choice else {
                isRunning = false
                return
            }
            settings.exportFormat = choice.format
            Task { await self.export(snapshot, as: choice.format, to: choice.url, window: window) }
        }
    }

    /// Writes `snapshot` to `url`; a failure goes to `reportError`.
    func export(_ snapshot: ExportSnapshot, as format: ExportFormat, to url: URL, window: NSWindow?) async {
        isRunning = true
        defer { isRunning = false }
        do {
            try await Self.write(snapshot, as: format, to: url)
        } catch {
            reportError(error, window)
        }
    }

    /// Renders `snapshot` to leave the app and writes it: an HTML page that follows its reader's light
    /// or dark with this Mac's system colors (other browsers know none of WebKit's), or a light PDF.
    /// Diagrams only mermaid.js draws come from the diagram stage first, as for the window's page.
    static func write(_ snapshot: ExportSnapshot, as format: ExportFormat, to url: URL) async throws {
        // Off the main actor, as the window's render does it (PERF-8): beautiful-mermaid lays a large
        // flowchart out for a second and more, and a context first made on the main thread leaves its
        // collector's timers there, where they wait out every later layout (probed 2026-09-29).
        let text = snapshot.text
        let sources = await Task.detached(priority: .userInitiated) { MermaidRenderer.unsupportedFences(in: text) }.value
        let diagrams = sources.isEmpty ? [:] : await DiagramWebRenderer.shared.render(sources, theme: snapshot.theme)
        let appearance: PageAppearance = format == .pdf ? .light : .system
        let systemColors = format == .html ? SystemColorResolver.current() : nil
        let html = await Task.detached(priority: .userInitiated) {
            MarkdownRenderer().renderExport(snapshot.text, title: snapshot.title, baseURL: snapshot.fileURL, theme: snapshot.theme, diagrams: diagrams,
                                            remoteContent: snapshot.remoteContent, attachments: snapshot.attachments,
                                            appearance: appearance, systemColors: systemColors)
        }.value
        switch format {
        case .html:
            try Data(html.utf8).write(to: url, options: .atomic)
        case .pdf:
            try await PDFExporter().write(html: html, title: snapshot.title, remoteContent: snapshot.remoteContent, to: url)
        }
    }

    private static func showAlert(_ error: Error, _ window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t Export"
        alert.informativeText = error.localizedDescription
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
