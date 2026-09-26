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
/// Two types are involved, the system's `net.daringfireball.markdown` (`md`, `markdown`) and Uncial's
/// own `UTType.markdownVariant` for the other extensions, each with its own remembered previous handler.
@Observable
final class DefaultAppManager {
    static let shared = DefaultAppManager(workspace: SystemWorkspace(), ownURL: Bundle.main.bundleURL, defaults: .standard)

    /// The types whose handler is set together; the first is the one the settings describe.
    static let types: [UTType] = [.markdown, .markdownVariant]
    static let previousDefaultKey = "previousDefaultMarkdownApp"
    static let textEditURL = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    /// Whether Uncial handles every type; `currentDefaultName` names the first app holding one instead.
    private(set) var isDefault: Bool?
    private(set) var currentDefaultName: String?
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    /// What the action that failed wanted: Uncial the default (Make Default) or not (the restore). Its
    /// error goes once a refresh finds that reached, fixed elsewhere or by a retry that took, instead of
    /// staying next to a healthy status for the session (BUG-34).
    private var failedGoal: Bool?

    private let workspace: DefaultAppWorkspace
    private let ownURL: URL
    private let defaults: UserDefaults

    init(workspace: DefaultAppWorkspace, ownURL: URL, defaults: UserDefaults) {
        self.workspace = workspace
        self.ownURL = ownURL
        self.defaults = defaults
    }

    func refresh() async {
        let handlers = Self.types.map { workspace.defaultApplicationURL(for: $0) }
        isDefault = handlers.allSatisfy { $0.map(isOwnApp) ?? false }
        let named: URL? = handlers.compactMap { $0 }.first { !isOwnApp($0) } ?? handlers[0]
        currentDefaultName = named?.deletingPathExtension().lastPathComponent
        if let failedGoal, isDefault == failedGoal {
            errorMessage = nil
            self.failedGoal = nil
        }
    }

    func makeDefault() async {
        await perform(goal: true) {
            for type in Self.types {
                if let current = self.workspace.defaultApplicationURL(for: type), !self.isOwnApp(current) {
                    self.defaults.set(current.path, forKey: Self.previousDefaultKey(for: type))
                }
                try await self.workspace.setDefaultApplication(at: self.ownURL, for: type)
            }
        }
    }

    func removeDefault() async {
        await perform(goal: false) {
            for type in Self.types {
                try await self.workspace.setDefaultApplication(at: self.restoreTarget(for: type), for: type)
            }
        }
    }

    /// Where `type`'s previous handler is remembered. The Markdown type keeps the original key, so a
    /// choice made before the variant type existed still restores.
    static func previousDefaultKey(for type: UTType) -> String {
        type == .markdown ? previousDefaultKey : previousDefaultKey + "." + type.identifier
    }

    /// The remembered previous handler of `type` when it still exists and is not Uncial, else the
    /// Markdown type's (a variant file had no handler of its own), else TextEdit.
    func restoreTarget(for type: UTType = .markdown) -> URL {
        let keys = type == .markdown ? [Self.previousDefaultKey] : [Self.previousDefaultKey(for: type), Self.previousDefaultKey]
        for key in keys {
            if let path = defaults.string(forKey: key), FileManager.default.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                if !isOwnApp(url) { return url }
            }
        }
        return Self.textEditURL
    }

    private func isOwnApp(_ url: URL) -> Bool {
        if let identifier = Bundle(url: url)?.bundleIdentifier, let own = Bundle(url: ownURL)?.bundleIdentifier {
            return identifier == own
        }
        return url.standardizedFileURL.path == ownURL.standardizedFileURL.path
    }

    private func perform(goal: Bool, _ work: @MainActor @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        failedGoal = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
            failedGoal = goal
        }
        await refresh()
    }
}
