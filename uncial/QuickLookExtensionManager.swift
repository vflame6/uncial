import Foundation
import Observation
import UncialCore

/// Installs (registers + elects) or removes (elects to ignore) the bundled Quick Look extension.
@Observable
final class QuickLookExtensionManager {
    static let shared = QuickLookExtensionManager()

    static let extensionIdentifier = "com.maksimradaev.uncial.QuickLook"

    private(set) var state: QuickLookExtensionState = .unknown
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    private var appexURL: URL? {
        Bundle.main.builtInPlugInsURL?.appendingPathComponent("UncialQuickLook.appex")
    }

    func refresh() async {
        do {
            let output = try await ShellCommand.run("/usr/bin/pluginkit", ["-m", "-i", Self.extensionIdentifier])
            state = QuickLookElection.parse(output)
        } catch {
            state = .unknown
            errorMessage = error.localizedDescription
        }
    }

    /// Registers the appex inside this app bundle and elects it for use.
    func install() async {
        await perform {
            if let appexURL = self.appexURL {
                _ = try await ShellCommand.run("/usr/bin/pluginkit", ["-a", appexURL.path])
            }
            _ = try await ShellCommand.run("/usr/bin/pluginkit", ["-e", "use", "-i", Self.extensionIdentifier])
        }
    }

    /// Same as switching the extension off in System Settings.
    func remove() async {
        await perform {
            _ = try await ShellCommand.run("/usr/bin/pluginkit", ["-e", "ignore", "-i", Self.extensionIdentifier])
        }
    }

    private func perform(_ work: @MainActor @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
            _ = try? await ShellCommand.run("/usr/bin/qlmanage", ["-r"])
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }
}
