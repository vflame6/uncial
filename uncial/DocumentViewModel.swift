import AppKit
import Foundation
import Observation
import UncialCore

/// Owns a document's text, its rendered body, and the file on disk.
///
/// The file is the source of truth: edits are written 0.5 s after typing stops (atomic write),
/// and external changes flow back in through `FileWatcher` unless local edits are pending.
@Observable
final class DocumentViewModel {
    let fileURL: URL?
    private(set) var text: String
    private(set) var body = ""
    private(set) var statistics: DocumentStatistics
    private(set) var loadError: String?
    private(set) var saveError: String?

    var title: String { fileURL?.lastPathComponent ?? "Markdown" }
    var hasUnsavedChanges: Bool { text != diskText }

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
        renderDelay: Duration = .milliseconds(150),
        saveDelay: Duration = .milliseconds(500)
    ) {
        self.fileURL = fileURL
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
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    /// The editor changed. Re-renders shortly and writes the file once typing pauses.
    func updateText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        scheduleRender()
        scheduleSave()
    }

    /// Writes the editor text now when it differs from the file.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let fileURL, hasUnsavedChanges else { return }
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
        let disk = MarkdownText.decode(data)
        switch DiskSync.decide(disk: disk, text: text, diskText: diskText) {
        case .ignore:
            break
        case .adopt:
            adopt(disk)
        case .keepLocal:
            diskText = disk
        }
    }

    private func adopt(_ disk: String) {
        saveTask?.cancel()
        saveTask = nil
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
        Task.detached(priority: .userInitiated) {
            let body = renderer.renderBody(text, baseURL: baseURL, sourcePositions: true)
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
