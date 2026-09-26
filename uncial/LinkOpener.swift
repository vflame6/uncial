import AppKit
import UncialCore
import UniformTypeIdentifiers

/// What a link opens through: `NSWorkspace`, or a fake in tests.
protocol LinkWorkspace {
    func open(_ url: URL) -> Bool
    func activateFileViewerSelecting(_ fileURLs: [URL])
    func urlForApplication(toOpen url: URL) -> URL?
}

extension NSWorkspace: LinkWorkspace {}

/// Opens a link clicked in the preview (or ⌘-clicked in Live Preview). A document is untrusted
/// and its link text can hide the target, so only web and mail links open straight away (in the
/// default browser or mail app) and local Markdown files in Uncial; any other file or URL scheme
/// is asked about first, naming the app that would open it; and programs, scripts, apps and
/// installers never open from a link: the question offers to show them in Finder instead.
enum LinkOpener {
    static let markdownExtensions = MarkdownText.fileExtensions
    /// Schemes that open without asking.
    static let trustedSchemes: Set<String> = ["http", "https", "mailto"]
    /// Files that run code or install something when opened.
    static let programTypes: [UTType] = [.executable, .application, .applicationBundle, .applicationExtension, .script,
                                         .shellScript, .unixExecutable, .systemPreferencesPane]
        + ["com.apple.installer-package-archive", "com.apple.installer-meta-package", "com.sun.java-archive",
           "com.apple.terminal.settings", "com.apple.applescript.script-bundle"].compactMap { UTType($0) }

    /// What a click does.
    enum Action: Equatable {
        /// Open in the default app without asking: a web or mail link.
        case open(URL)
        /// Open in Uncial: a local Markdown file.
        case openDocument(URL)
        /// Ask, then open: any other file or URL scheme.
        case confirm(URL)
        /// Never open; offer to show it in Finder: a program, script, app or installer.
        case reveal(URL)
    }

    /// The question asked before a `confirm` or `reveal` action.
    struct Question: Equatable {
        let message: String
        let detail: String
        let confirmTitle: String
    }

    /// Opens `url` per `action(for:from:attachments:)`, asking on a sheet over `window` (or in an
    /// app-modal alert without one) where it has to.
    static func open(_ url: URL, from directory: URL? = nil, attachments: AttachmentSearch = .direct, in window: NSWindow? = nil) {
        perform(action(for: url, from: directory, attachments: attachments), in: window, workspace: NSWorkspace.shared) { question, window, answer in
            ask(question, in: window, answer: answer)
        }
    }

    /// Decides what a click on `url` does; a local file that is not where `url` says is looked for
    /// by `attachments` from `directory` (the document's folder) first.
    static func action(for url: URL, from directory: URL?, attachments: AttachmentSearch) -> Action {
        guard url.isFileURL else {
            return trustedSchemes.contains(url.scheme?.lowercased() ?? "") ? .open(url) : .confirm(url)
        }
        let fileURL = resolve(url, from: directory, attachments: attachments)
        if markdownExtensions.contains(fileURL.pathExtension.lowercased()) {
            return .openDocument(fileURL)
        }
        let type = (try? fileURL.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: fileURL.pathExtension)
        if let type, programTypes.contains(where: { type.conforms(to: $0) }) {
            return .reveal(fileURL)
        }
        return .confirm(fileURL)
    }

    /// Carries out `action`: asks through `ask` first unless it opens a web or mail link or a
    /// Markdown file.
    static func perform(_ action: Action, in window: NSWindow?, workspace: LinkWorkspace,
                        ask: (Question, NSWindow?, @escaping (Bool) -> Void) -> Void) {
        switch action {
        case .open(let url):
            _ = workspace.open(url)
        case .openDocument(let url):
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if error != nil {
                    _ = workspace.open(url)
                }
            }
        case .confirm(let url):
            guard let application = workspace.urlForApplication(toOpen: url) else { return }
            ask(confirmation(for: url, application: application), window) { approved in
                if approved { _ = workspace.open(url) }
            }
        case .reveal(let url):
            ask(revealQuestion(for: url), window) { approved in
                if approved { workspace.activateFileViewerSelecting([url]) }
            }
        }
    }

    static func confirmation(for url: URL, application: URL) -> Question {
        let app = FileManager.default.displayName(atPath: application.path)
        let name = url.isFileURL ? url.lastPathComponent : url.absoluteString
        return Question(message: "Open “\(name)”?",
                        detail: "The link in this document opens it with \(app).",
                        confirmTitle: "Open")
    }

    static func revealQuestion(for url: URL) -> Question {
        Question(message: "“\(url.lastPathComponent)” is a program, script or installer.",
                 detail: "Uncial doesn't run programs from links in a document. You can show it in Finder and decide there.",
                 confirmTitle: "Show in Finder")
    }

    /// The question as an alert: a sheet over `window`, or app-modal without one.
    static func ask(_ question: Question, in window: NSWindow?, answer: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = question.message
        alert.informativeText = question.detail
        alert.addButton(withTitle: question.confirmTitle)
        alert.addButton(withTitle: "Cancel")
        if let window, window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window) { answer($0 == .alertFirstButtonReturn) }
        } else {
            answer(alert.runModal() == .alertFirstButtonReturn)
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
