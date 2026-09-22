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
    let fileURL: URL?
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
    /// Unsaved edits that nothing will write on its own (a manually saved document, or an external
    /// change awaiting its answer): closing, quitting and reverting ask first.
    var needsSavePrompt: Bool { hasUnsavedChanges && (!autosaves || pendingExternalChange != nil) }

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

    /// What happens when the file changes while the window holds unsaved edits (`AppSettings.externalChangePolicy`).
    var externalChangePolicy: ExternalChangePolicy = .ask
    /// Asked, under the Ask policy, with the document's name: keep the edits or reload the file. The
    /// window's guard answers with a sheet; without one (no window yet) the edits stay.
    @ObservationIgnored var externalChangeResolver: ((String) async -> ExternalChangeChoice)?
    /// The disk text waiting for an answer; nothing is written meanwhile.
    private(set) var pendingExternalChange: String?

    /// What we last loaded from or wrote to the file.
    private var diskText: String
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
        theme: Theme = .default,
        renderDelay: Duration = .milliseconds(150),
        saveDelay: Duration = .milliseconds(500)
    ) {
        self.fileURL = fileURL
        self.theme = theme
        self.renderDelay = renderDelay
        self.saveDelay = saveDelay
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
    /// a manually saved document keeps them for File ▸ Save.
    func saveIfAutomatic() {
        if autosaves {
            saveNow()
        }
    }

    /// Writes the editor text now when it differs from the file. A change another program made
    /// that the watcher has not reported yet gets the same treatment as a reported one first, so the
    /// write never lands blindly; an explicit save while the Ask question is open keeps the edits.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let fileURL, hasUnsavedChanges else { return }
        if pendingExternalChange == nil, let data = try? Data(contentsOf: fileURL), !reconcile(disk: MarkdownText.decode(data)) {
            return
        }
        pendingExternalChange = nil
        let textToSave = text
        do {
            try Data(textToSave.utf8).write(to: fileURL, options: .atomic)
            diskText = textToSave
            saveError = nil
            syncDocumentModificationDate(for: fileURL)
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Re-reads the file and adopts its contents, discarding unsaved edits.
    func reload() {
        guard let fileURL else { return }
        do {
            adopt(MarkdownText.decode(try Data(contentsOf: fileURL)))
        } catch {
            loadError = error.localizedDescription
        }
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
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        _ = reconcile(disk: MarkdownText.decode(data))
    }

    /// Applies the file's current text per `DiskSync` and, with local edits pending, the policy.
    /// Returns whether the editor text may be written now: not when the file was adopted, and not
    /// while the Ask question is open (its answer decides).
    private func reconcile(disk: String) -> Bool {
        switch DiskSync.decide(disk: disk, text: text, diskText: diskText) {
        case .ignore:
            return true
        case .adopt:
            adopt(disk)
            return false
        case .keepLocal:
            switch externalChangePolicy {
            case .keepLocal:
                diskText = disk
                return true
            case .reload:
                adopt(disk)
                return false
            case .ask:
                askAboutExternalChange(disk)
                return false
            }
        }
    }

    /// Holds the pending save and asks; a further change while the question is open only updates
    /// what a reload would adopt.
    private func askAboutExternalChange(_ disk: String) {
        saveTask?.cancel()
        saveTask = nil
        if pendingExternalChange != nil {
            pendingExternalChange = disk
            return
        }
        pendingExternalChange = disk
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
        guard let disk = pendingExternalChange else { return }
        pendingExternalChange = nil
        switch choice {
        case .keepLocal:
            diskText = disk
            if autosaves { scheduleSave() }
        case .reload:
            adopt(disk)
        }
    }

    private func adopt(_ disk: String) {
        saveTask?.cancel()
        saveTask = nil
        pendingExternalChange = nil
        diskText = disk
        loadError = nil
        if text != disk {
            text = disk
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
        Task.detached(priority: .userInitiated) {
            // Diagrams beautiful-mermaid cannot draw go through mermaid.js in the hidden web view first.
            let sources = MermaidRenderer.unsupportedFences(in: text)
            let diagrams = sources.isEmpty ? [:] : await DiagramWebRenderer.shared.render(sources, theme: theme)
            let body = renderer.renderBody(text, baseURL: baseURL, sourcePositions: true, diagrams: diagrams, remoteContent: remoteContent)
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
