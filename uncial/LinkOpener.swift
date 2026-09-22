import AppKit
import UncialCore

/// External links go to the default browser; local Markdown files open in Uncial; other files open with their default app.
enum LinkOpener {
    static let markdownExtensions = MarkdownText.fileExtensions

    /// Opens `url`. A local file that is not where `url` says is looked for by `attachments` from
    /// `directory` (the document's folder) first.
    static func open(_ url: URL, from directory: URL? = nil, attachments: AttachmentSearch = .direct) {
        guard url.isFileURL else {
            NSWorkspace.shared.open(url)
            return
        }
        let fileURL = resolve(url, from: directory, attachments: attachments)
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

    /// The local file a `file:` link stands for: the file itself (query and fragment dropped) or,
    /// when nothing is there, the attachment `attachments` finds from `directory`.
    static func resolve(_ url: URL, from directory: URL?, attachments: AttachmentSearch) -> URL {
        let fileURL = URL(fileURLWithPath: url.path)
        guard let directory else { return fileURL }
        return attachments.locate(fileURL, from: directory) ?? fileURL
    }
}
