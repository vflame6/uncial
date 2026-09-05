import Foundation
import Observation
import UncialCore

@Observable
final class DocumentViewModel {
    let fileURL: URL?
    private(set) var html = ""
    private(set) var error: String?

    private let renderer = MarkdownRenderer()
    private var watcher: FileWatcher?
    private var generation = 0

    init(fileURL: URL?, initialText: String) {
        self.fileURL = fileURL
        render(initialText)
        watch()
    }

    /// Re-reads the file from disk and re-renders. Stale results are dropped.
    func reload() {
        guard let fileURL else { return }
        generation += 1
        let generation = generation
        let renderer = renderer
        let title = fileURL.lastPathComponent
        Task.detached(priority: .userInitiated) {
            let result: Result<String, Error>
            do {
                let data = try Data(contentsOf: fileURL)
                result = .success(renderer.renderDocument(MarkdownText.decode(data), title: title, baseURL: fileURL))
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                switch result {
                case .success(let html):
                    self.html = html
                    self.error = nil
                case .failure(let error):
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func render(_ text: String) {
        generation += 1
        let generation = generation
        let renderer = renderer
        let title = fileURL?.lastPathComponent ?? "Markdown"
        let baseURL = fileURL
        Task.detached(priority: .userInitiated) {
            let html = renderer.renderDocument(text, title: title, baseURL: baseURL)
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation else { return }
                self.html = html
            }
        }
    }

    private func watch() {
        guard let fileURL else { return }
        let watcher = FileWatcher(url: fileURL) { [weak self] in self?.reload() }
        watcher.start()
        self.watcher = watcher
    }
}
