import Foundation
import Observation
import UncialCore

/// Installs (registers + elects) or removes (elects to ignore) the bundled Quick Look extensions:
/// the preview (Space in Finder) and the thumbnail (Finder icons, Open panels). The state shown
/// is the preview's; the thumbnail follows it.
@Observable
final class QuickLookExtensionManager {
    static let shared = QuickLookExtensionManager()

    static let extensionIdentifier = "com.maksimradaev.uncial.QuickLook"
    static let thumbnailIdentifier = "com.maksimradaev.uncial.Thumbnail"

    private(set) var state: QuickLookExtensionState = .unknown
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    /// The state the action that failed wanted; its error goes once a refresh finds that reached
    /// (switched in System Settings, say) instead of staying next to a healthy status (BUG-34).
    private var failedGoal: QuickLookExtensionState?
    /// Runs `pluginkit`, `qlmanage` and `killall`; tests put a stand-in here.
    @ObservationIgnored var runCommand: (String, [String]) async throws -> String = ShellCommand.run

    private var appexURLs: [URL] {
        guard let plugIns = Bundle.main.builtInPlugInsURL else { return [] }
        return ["UncialQuickLook.appex", "UncialThumbnail.appex"].map { plugIns.appendingPathComponent($0) }
    }

    func refresh() async {
        do {
            let output = try await runCommand("/usr/bin/pluginkit", ["-m", "-i", Self.extensionIdentifier])
            state = QuickLookElection.parse(output)
            // A refresh's own error goes with the next one that works; an action's once its goal is reached.
            if failedGoal == nil || failedGoal == state {
                errorMessage = nil
                failedGoal = nil
            }
        } catch {
            state = .unknown
            errorMessage = error.localizedDescription
        }
    }

    /// Registers the appexes inside this app bundle and elects them for use.
    func install() async {
        await perform(goal: .enabled) {
            for appexURL in self.appexURLs where FileManager.default.fileExists(atPath: appexURL.path) {
                _ = try await self.runCommand("/usr/bin/pluginkit", ["-a", appexURL.path])
            }
            for identifier in [Self.extensionIdentifier, Self.thumbnailIdentifier] {
                _ = try await self.runCommand("/usr/bin/pluginkit", ["-e", "use", "-i", identifier])
            }
        }
    }

    /// Same as switching the extensions off in System Settings.
    func remove() async {
        await perform(goal: .disabled) {
            for identifier in [Self.extensionIdentifier, Self.thumbnailIdentifier] {
                _ = try await self.runCommand("/usr/bin/pluginkit", ["-e", "ignore", "-i", identifier])
            }
        }
    }

    private func perform(goal: QuickLookExtensionState, _ work: @MainActor @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        failedGoal = nil
        defer { isBusy = false }
        do {
            try await work()
            _ = try? await runCommand("/usr/bin/qlmanage", ["-r"])
            _ = try? await runCommand("/usr/bin/qlmanage", ["-r", "cache"])
            // The thumbnail agent lists extensions once at launch and ignores SIGTERM; launchd
            // brings it back on the next request, now seeing this copy's extension.
            _ = try? await runCommand("/usr/bin/killall", ["-KILL", "com.apple.quicklook.ThumbnailsAgent"])
        } catch {
            errorMessage = error.localizedDescription
            failedGoal = goal
        }
        await refresh()
    }
}
