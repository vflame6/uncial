import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
protocol DefaultAppWorkspace: AnyObject {
    func defaultApplicationURL(for type: UTType) -> URL?
    func setDefaultApplication(at url: URL, for type: UTType) async throws
}

/// NSWorkspace-backed implementation. LaunchServices rejects a second change made right after
/// another one (userCanceledErr), so a failed call is retried once after a short pause.
final class SystemWorkspace: DefaultAppWorkspace {
    func defaultApplicationURL(for type: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    func setDefaultApplication(at url: URL, for type: UTType) async throws {
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: url, toOpen: type)
        } catch {
            try await Task.sleep(for: .seconds(1))
            try await NSWorkspace.shared.setDefaultApplication(at: url, toOpen: type)
        }
    }
}

/// Makes Uncial the default app for Markdown files, or hands the role back to the previous app.
@Observable
final class DefaultAppManager {
    static let shared = DefaultAppManager(workspace: SystemWorkspace(), ownURL: Bundle.main.bundleURL, defaults: .standard)

    static let previousDefaultKey = "previousDefaultMarkdownApp"
    static let textEditURL = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    private(set) var isDefault: Bool?
    private(set) var currentDefaultName: String?
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    private let workspace: DefaultAppWorkspace
    private let ownURL: URL
    private let defaults: UserDefaults

    init(workspace: DefaultAppWorkspace, ownURL: URL, defaults: UserDefaults) {
        self.workspace = workspace
        self.ownURL = ownURL
        self.defaults = defaults
    }

    func refresh() async {
        let current = workspace.defaultApplicationURL(for: .markdown)
        isDefault = current.map(isOwnApp) ?? false
        currentDefaultName = current?.deletingPathExtension().lastPathComponent
    }

    func makeDefault() async {
        await perform {
            if let current = self.workspace.defaultApplicationURL(for: .markdown), !self.isOwnApp(current) {
                self.defaults.set(current.path, forKey: Self.previousDefaultKey)
            }
            try await self.workspace.setDefaultApplication(at: self.ownURL, for: .markdown)
        }
    }

    func removeDefault() async {
        await perform {
            try await self.workspace.setDefaultApplication(at: self.restoreTarget(), for: .markdown)
        }
    }

    /// The remembered previous handler when it still exists and is not Uncial; otherwise TextEdit.
    func restoreTarget() -> URL {
        if let path = defaults.string(forKey: Self.previousDefaultKey),
           FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if !isOwnApp(url) { return url }
        }
        return Self.textEditURL
    }

    private func isOwnApp(_ url: URL) -> Bool {
        if let identifier = Bundle(url: url)?.bundleIdentifier, let own = Bundle(url: ownURL)?.bundleIdentifier {
            return identifier == own
        }
        return url.standardizedFileURL.path == ownURL.standardizedFileURL.path
    }

    private func perform(_ work: @MainActor @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }
}
