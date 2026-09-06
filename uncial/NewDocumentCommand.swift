import AppKit
import UniformTypeIdentifiers

/// File ▸ New…: asks where to create an empty Markdown file, writes it, and opens it.
enum NewDocumentCommand {
    static func run() {
        let panel = NSSavePanel()
        panel.title = "New Markdown File"
        panel.nameFieldStringValue = "Untitled.md"
        panel.allowedContentTypes = [.markdown]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data().write(to: url)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                NSAlert(error: error).runModal()
            }
        }
    }
}
