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

    private var appexURLs: [URL] {
        guard let plugIns = Bundle.main.builtInPlugInsURL else { return [] }
        return ["UncialQuickLook.appex", "UncialThumbnail.appex"].map { plugIns.appendingPathComponent($0) }
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

    /// Registers the appexes inside this app bundle and elects them for use.
    func install() async {
        await perform {
            for appexURL in self.appexURLs where FileManager.default.fileExists(atPath: appexURL.path) {
                _ = try await ShellCommand.run("/usr/bin/pluginkit", ["-a", appexURL.path])
            }
            for identifier in [Self.extensionIdentifier, Self.thumbnailIdentifier] {
                _ = try await ShellCommand.run("/usr/bin/pluginkit", ["-e", "use", "-i", identifier])
            }
        }
    }

    /// Same as switching the extensions off in System Settings.
    func remove() async {
        await perform {
            for identifier in [Self.extensionIdentifier, Self.thumbnailIdentifier] {
                _ = try await ShellCommand.run("/usr/bin/pluginkit", ["-e", "ignore", "-i", identifier])
            }
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
            _ = try? await ShellCommand.run("/usr/bin/qlmanage", ["-r", "cache"])
            // The thumbnail agent lists extensions once at launch and ignores SIGTERM; launchd
            // brings it back on the next request, now seeing this copy's extension.
            _ = try? await ShellCommand.run("/usr/bin/killall", ["-KILL", "com.apple.quicklook.ThumbnailsAgent"])
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }
}
