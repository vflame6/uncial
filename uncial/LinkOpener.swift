import AppKit

/// External links go to the default browser; local Markdown files open in Uncial; other files open with their default app.
enum LinkOpener {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mkdown", "mdwn", "mdtxt", "mdtext"]

    static func open(_ url: URL) {
        guard url.isFileURL else {
            NSWorkspace.shared.open(url)
            return
        }
        let fileURL = URL(fileURLWithPath: url.path)
        guard markdownExtensions.contains(fileURL.pathExtension.lowercased()) else {
            NSWorkspace.shared.open(fileURL)
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { _, _, error in
            if error != nil {
                NSWorkspace.shared.open(fileURL)
            }
        }
    }
}
