import AppKit
import Foundation
import Observation
import UncialCore

/// Owns a document's text, its rendered body, and the file on disk.
///
/// The file is the source of truth. With `autosaves` on, edits are written 0.5 s after typing stops
/// (atomic write); off, they wait for `saveNow()` (File ▸ Save) and `needsSavePrompt` tells the
/// window to ask before closing. External changes flow back in through `FileWatcher`; with local
/// edits pending, `externalChangePolicy` decides (ask on a sheet, keep the edits, reload).
@Observable
final class DocumentViewModel {
    private(set) var fileURL: URL?
    private(set) var text: String
    private(set) var body = ""
    private(set) var statistics: DocumentStatistics
    private(set) var loadError: String?
    private(set) var saveError: String?

    var title: String { fileURL?.lastPathComponent ?? "Markdown" }
    /// The document theme: mermaid.js bakes its colors into the diagrams it draws, so a change re-renders.
    var theme: Theme {
        didSet { if theme != oldValue { render() } }
    }
    var hasUnsavedChanges: Bool { text != diskText }
    /// Unsaved edits that nothing will write on its own (a manually saved document, an external
    /// change awaiting its answer, or an automatic save that failed): closing, quitting and
    /// reverting ask first.
    var needsSavePrompt: Bool { hasUnsavedChanges && (!autosaves || pendingExternalChange != nil || saveError != nil) }

    /// Whether edits are written shortly after typing pauses (`AppSettings.autosave`). Changing the
    /// policy settles the file: what was typed under either promise is written right away.
    var autosaves = false {
        didSet { if autosaves != oldValue { saveNow() } }
    }

    /// Whether the rendered page may reference the web (`AppSettings.loadRemoteContent`); off, the
    /// renderer disarms such references, and the web view blocks the loads on top of that.
    var remoteContent = false {
        didSet { if remoteContent != oldValue { render() } }
    }

    /// Where an image that is not where the document says is looked for (`AppSettings.attachmentSearch`).
    var attachmentSearch: AttachmentSearch = .direct {
        didSet { if attachmentSearch != oldValue { render() } }
    }

    /// What happens when the file changes while the window holds unsaved edits (`AppSettings.externalChangePolicy`).
    var externalChangePolicy: ExternalChangePolicy = .ask
    /// Asked, under the Ask policy, with the document's name: keep the edits or reload the file. The
    /// window's guard answers with a sheet; without one (no window yet) the edits stay.
    @ObservationIgnored var externalChangeResolver: ((String) async -> ExternalChangeChoice)?
    /// The disk text waiting for an answer; nothing is written meanwhile.
    var pendingExternalChange: String? { pendingDisk?.text }
    private var pendingDisk: MarkdownText.Decoded?

    /// What we last loaded from or wrote to the file.
    private var diskText: String
    /// The encoding saving writes (`MarkdownText.Decoded.encoding`): the file's own for a legacy
    /// encoding, UTF-8 otherwise or when a typed character does not fit it.
    private(set) var encoding: String.Encoding
    /// The text was read with replacement characters (`MarkdownText.Decoded.isLossy`), so it is not written back.
    private var isLossy: Bool
    private let renderer = MarkdownRenderer()
    private let renderDelay: Duration
    private let saveDelay: Duration
    private var watcher: FileWatcher?
    private var renderTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var generation = 0
    private var terminationObserver: NSObjectProtocol?

    init(
        fileURL: URL?,
        initialText: String,
        encoding: String.Encoding = .utf8,
        isLossy: Bool = false,
        theme: Theme = .default,
        renderDelay: Duration = .milliseconds(150),
        saveDelay: Duration = .milliseconds(500)
    ) {
        self.fileURL = fileURL
        self.theme = theme
        self.renderDelay = renderDelay
        self.saveDelay = saveDelay
        self.encoding = encoding
        self.isLossy = isLossy
        text = initialText
        diskText = initialText
        statistics = DocumentStatistics(text: initialText)
        render()
        watch()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveIfAutomatic() }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    /// The editor changed. Re-renders shortly and, when saving is automatic, writes the file once
    /// typing pauses.
    func updateText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        scheduleRender()
        if autosaves {
            scheduleSave()
        }
    }

    /// Writes pending edits now when saving is automatic (leaving an editing mode, closing, quitting);
    /// a manually saved document keeps them for File ▸ Save, and nothing is written while the Ask
    /// question is open.
    func saveIfAutomatic() {
        if autosaves, pendingExternalChange == nil {
            saveNow()
        }
    }

    /// What a save did.
    enum SaveOutcome: Equatable {
        /// The editor text is on disk.
        case written
        /// Nothing to write: no unsaved edits, or no file.
        case unchanged
        /// The file changed under the edits and the Ask policy wants an answer first; nothing was written.
        case needsDecision
        /// The file changed and its contents replaced the edits (the Reload policy).
        case adopted
        /// The write failed; `saveError` says why.
        case failed
    }

    /// Writes the editor text now when it differs from the file. A change another program made
    /// that the watcher has not reported yet gets the same treatment as a reported one first, so the
    /// write never lands blindly; an explicit save while the Ask question is open keeps the edits.
    @discardableResult
    func saveNow() -> SaveOutcome {
        save(asking: true)
    }

    /// `saveNow()` for a window about to close or quit, which asks about a change on disk itself,
    /// on its own sheet: the change is held (`.needsDecision`) instead of asked about, and an open
    /// question is not overridden.
    func saveBeforeClosing() -> SaveOutcome {
        save(asking: false)
    }

    private func save(asking: Bool) -> SaveOutcome {
        saveTask?.cancel()
        saveTask = nil
        guard let fileURL, hasUnsavedChanges else { return .unchanged }
        guard !isLossy else {
            saveError = "“\(title)” is in a text encoding Uncial could not read without loss; saving would replace the characters it could not read."
            return .failed
        }
        if pendingDisk != nil {
            guard asking else { return .needsDecision }
        } else if let disk = try? read(fileURL) {
            switch reconcile(disk: disk, asking: asking) {
            case .write: break
            case .adopted: return .adopted
            case .pending: return .needsDecision
            }
        }
        pendingDisk = nil
        let textToSave = text
        // The file's own encoding when every character fits (a legacy file keeps its bytes), UTF-8 otherwise.
        let legacy = encoding == .utf8 ? nil : textToSave.data(using: encoding, allowLossyConversion: false)
        do {
            try Self.write(legacy ?? Data(textToSave.utf8), to: fileURL)
            diskText = textToSave
            if legacy == nil { encoding = .utf8 }
            saveError = nil
            syncDocumentModificationDate(for: fileURL)
            return .written
        } catch {
            saveError = error.localizedDescription
            return .failed
        }
    }

    /// The document was renamed or moved while open (Finder, `mv`, a sync client): saving,
    /// watching, the title and relative images follow it to `url`.
    func relocate(to url: URL?) {
        guard url != fileURL else { return }
        watcher?.stop()
        watcher = nil
        fileURL = url
        watch()
        render()
    }

    /// Re-reads the file and adopts its contents, discarding unsaved edits.
    func reload() {
        guard let fileURL else { return }
        do {
            adopt(try read(fileURL))
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Safe save the way NSDocument does it: the bytes go into a file in the item-replacement directory
    /// on the document's volume, which FileManager then swaps in. The swap keeps the original's Finder
    /// tags, other extended attributes, permissions and creation date, which an atomic write (a new file
    /// renamed over the old one) dropped. A volume without that directory gets the atomic write.
    private static func write(_ data: Data, to fileURL: URL) throws {
        let fileManager = FileManager.default
        guard let directory = try? fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                   appropriateFor: fileURL, create: true) else {
            try data.write(to: fileURL, options: .atomic)
            return
        }
        defer { try? fileManager.removeItem(at: directory) }
        let replacement = directory.appendingPathComponent(fileURL.lastPathComponent)
        try data.write(to: replacement)
        _ = try fileManager.replaceItemAt(fileURL, withItemAt: replacement)
    }

    /// The file's text, read the way it was read before when its bytes are not UTF-8.
    private func read(_ fileURL: URL) throws -> MarkdownText.Decoded {
        MarkdownText.read(try Data(contentsOf: fileURL), preferring: encoding)
    }

    // MARK: - Private

    /// NSDocument compares the file's modification date with the one it recorded before an autosave
    /// and reports "changed by another application" when they differ; after the model's own write
    /// they always do. Keep its record current.
    private func syncDocumentModificationDate(for fileURL: URL) {
        guard let document = NSDocumentController.shared.document(for: fileURL),
              let date = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date else { return }
        document.fileModificationDate = date
    }

    private func syncFromDisk() {
        guard let fileURL, let disk = try? read(fileURL) else { return }
        // While the question is open, Reload adopts what the file holds now, whatever it is: a change
        // back to the saved text would otherwise pass for our own write and leave the older change
        // pending, and Reload would show text the file no longer has, marked as saved.
        if pendingDisk != nil {
            pendingDisk = disk
            return
        }
        _ = reconcile(disk: disk)
    }

    /// What `reconcile` left for the editor text.
    private enum Reconciled {
        /// It may be written now.
        case write
        /// The file's contents replaced it.
        case adopted
        /// The Ask question holds it until answered.
        case pending
    }

    /// Applies the file's current text per `DiskSync` and, with local edits pending, the policy.
    /// Under the Ask policy the question is asked through `externalChangeResolver`, unless `asking`
    /// is off: then the change is only held, for a closing window to ask about itself.
    private func reconcile(disk: MarkdownText.Decoded, asking: Bool = true) -> Reconciled {
        switch DiskSync.decide(disk: disk.text, text: text, diskText: diskText) {
        case .ignore:
            return .write
        case .adopt:
            adopt(disk)
            return .adopted
        case .keepLocal:
            switch externalChangePolicy {
            case .keepLocal:
                diskText = disk.text
                return .write
            case .reload:
                adopt(disk)
                return .adopted
            case .ask:
                if asking {
                    askAboutExternalChange(disk)
                } else {
                    saveTask?.cancel()
                    saveTask = nil
                    pendingDisk = disk
                }
                return .pending
            }
        }
    }

    /// Holds the pending save and asks; a further change while the question is open only updates
    /// what a reload would adopt.
    private func askAboutExternalChange(_ disk: MarkdownText.Decoded) {
        saveTask?.cancel()
        saveTask = nil
        if pendingDisk != nil {
            pendingDisk = disk
            return
        }
        pendingDisk = disk
        guard let externalChangeResolver else {
            resolveExternalChange(.keepLocal)
            return
        }
        let name = title
        Task { @MainActor [weak self] in
            let choice = await externalChangeResolver(name)
            self?.resolveExternalChange(choice)
        }
    }

    /// Settles a pending external change: keep the edits (the file's new contents go at the next
    /// save, right away with automatic saving) or reload the file and drop them.
    func resolveExternalChange(_ choice: ExternalChangeChoice) {
        guard let disk = pendingDisk else { return }
        pendingDisk = nil
        switch choice {
        case .keepLocal:
            diskText = disk.text
            if autosaves { scheduleSave() }
        case .reload:
            adopt(disk)
        }
    }

    private func adopt(_ disk: MarkdownText.Decoded) {
        saveTask?.cancel()
        saveTask = nil
        pendingDisk = nil
        diskText = disk.text
        encoding = disk.encoding
        isLossy = disk.isLossy
        loadError = nil
        saveError = nil
        if text != disk.text {
            text = disk.text
        }
        render()
    }

    private func scheduleRender() {
        renderTask?.cancel()
        let delay = renderDelay
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.render()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard pendingExternalChange == nil else { return }
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func render() {
        generation += 1
        let generation = generation
        let renderer = renderer
        let text = text
        let baseURL = fileURL
        let theme = theme
        let remoteContent = remoteContent
        let attachments = attachmentSearch
        Task.detached(priority: .userInitiated) {
            // Diagrams beautiful-mermaid cannot draw go through mermaid.js in the hidden web view first.
            let sources = MermaidRenderer.unsupportedFences(in: text)
            let diagrams = sources.isEmpty ? [:] : await DiagramWebRenderer.shared.render(sources, theme: theme)
            let body = renderer.renderBody(text, baseURL: baseURL, sourcePositions: true, diagrams: diagrams, remoteContent: remoteContent, attachments: attachments)
            let statistics = DocumentStatistics(text: text)
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                self.body = body
                self.statistics = statistics
            }
        }
    }

    private func watch() {
        guard let fileURL else { return }
        let watcher = FileWatcher(url: fileURL) { [weak self] in self?.syncFromDisk() }
        watcher.start()
        self.watcher = watcher
    }
}
