import Foundation
import Observation

/// Where the `uncial` command stands, as Settings ▸ General ▸ Command Line shows it.
enum CommandLineToolState: Equatable {
    /// A link to this copy's script in `folder`.
    case installed(folder: String)
    /// Homebrew's link to this copy: the cask installed it and removes it.
    case homebrew
    /// A link to the script inside another copy of Uncial, at `app` (a build folder, an older download).
    case otherCopy(app: String)
    /// A file at `path` that is not Uncial's; it is left alone.
    case taken(path: String)
    case notInstalled

    /// The command is on the PATH and opens this copy.
    var isAvailable: Bool {
        switch self {
        case .installed, .homebrew: true
        case .otherCopy, .taken, .notInstalled: false
        }
    }
}

/// What `CommandLineToolManager` asks of the file system; tests pass an in-memory one.
struct CommandLineFileSystem {
    enum Item: Equatable {
        case nothing
        case link(to: String)
        case file
    }

    var item: (_ path: String) -> Item
    var exists: (_ path: String) -> Bool
    var isWritableDirectory: (_ path: String) -> Bool
    var createLink: (_ path: String, _ destination: String) throws -> Void
    var remove: (_ path: String) throws -> Void

    static let live = CommandLineFileSystem(
        item: { path in
            if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
                return .link(to: destination)
            }
            return FileManager.default.fileExists(atPath: path) ? .file : .nothing
        },
        exists: { FileManager.default.fileExists(atPath: $0) },
        isWritableDirectory: { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
                && FileManager.default.isWritableFile(atPath: path)
        },
        createLink: { try FileManager.default.createSymbolicLink(atPath: $0, withDestinationPath: $1) },
        remove: { try FileManager.default.removeItem(atPath: $0) }
    )
}

/// Puts the `uncial` command on the PATH or takes it off: a symbolic link in /usr/local/bin to the
/// script inside this copy of the app (Contents/Resources/uncial). That folder usually needs an
/// administrator, whose password the system asks for; Homebrew's link (the cask's `binary`) is left to
/// Homebrew.
@Observable
final class CommandLineToolManager {
    static let shared = CommandLineToolManager()

    /// Where Install puts the link: on every shell's default PATH (/etc/paths).
    static let installFolder = "/usr/local/bin"
    /// Where a link is looked for: Install's folder, then Homebrew's on Apple silicon (on Intel it is /usr/local/bin).
    static let folders = ["/usr/local/bin", "/opt/homebrew/bin"]
    /// A cask install's record; with one, a link to this copy is Homebrew's.
    static let caskrooms = ["/opt/homebrew/Caskroom/uncial", "/usr/local/Caskroom/uncial"]
    private static let scriptSuffix = "/Contents/Resources/uncial"

    private(set) var state: CommandLineToolState = .notInstalled
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    /// The script in this copy of Uncial.
    @ObservationIgnored var scriptPath: String? = Bundle.main.path(forResource: "uncial", ofType: nil)
    @ObservationIgnored var fileSystem = CommandLineFileSystem.live
    /// Runs a shell command as root once the user gives an administrator's password, the second
    /// argument saying why; throws `Cancelled` when the user cancels.
    @ObservationIgnored var runAsAdministrator: (String, String) async throws -> Void = CommandLineToolManager.runWithOsascript

    struct Cancelled: Error {}

    /// A copy of Uncial opened from a download without being moved runs from a random read-only place
    /// (App Translocation) that a link cannot keep pointing at.
    var isTranslocated: Bool { scriptPath?.contains("/AppTranslocation/") == true }

    func refresh() {
        state = currentState()
    }

    private func currentState() -> CommandLineToolState {
        let ours = scriptPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        for folder in Self.folders {
            let path = folder + "/uncial"
            switch fileSystem.item(path) {
            case .nothing:
                continue
            case .file:
                return .taken(path: path)
            case .link(let destination):
                let target = URL(fileURLWithPath: destination, relativeTo: URL(fileURLWithPath: folder, isDirectory: true)).standardizedFileURL.path
                if target == ours {
                    return Self.caskrooms.contains(where: fileSystem.exists) ? .homebrew : .installed(folder: folder)
                }
                if target.hasSuffix(".app" + Self.scriptSuffix) {
                    return .otherCopy(app: String(target.dropLast(Self.scriptSuffix.count)))
                }
                return .taken(path: path)
            }
        }
        return .notInstalled
    }

    /// Links /usr/local/bin/uncial to this copy's script, as an administrator when the folder is not the
    /// user's to write (or not there yet). Leaves a file that is not Uncial's, Homebrew's link and a
    /// translocated copy alone.
    func install() async {
        refresh()
        guard let script = scriptPath, !isTranslocated else { return }
        switch state {
        case .taken, .homebrew: return
        case .installed, .otherCopy, .notInstalled: break
        }
        let link = Self.installFolder + "/uncial"
        await perform {
            if self.fileSystem.isWritableDirectory(Self.installFolder) {
                if case .link = self.fileSystem.item(link) {
                    try self.fileSystem.remove(link)
                }
                try self.fileSystem.createLink(link, script)
            } else {
                try await self.runAsAdministrator(
                    "/bin/mkdir -p \(Self.shellQuoted(Self.installFolder)) && /bin/ln -sfh \(Self.shellQuoted(script)) \(Self.shellQuoted(link))",
                    "Uncial wants to install the uncial command in \(Self.installFolder)."
                )
            }
        }
    }

    /// Removes the link to this copy (never Homebrew's), as an administrator when its folder is not the user's.
    func remove() async {
        refresh()
        guard case .installed(let folder) = state else { return }
        let link = folder + "/uncial"
        await perform {
            if self.fileSystem.isWritableDirectory(folder) {
                try self.fileSystem.remove(link)
            } else {
                try await self.runAsAdministrator(
                    "/bin/test -L \(Self.shellQuoted(link)) && /bin/rm \(Self.shellQuoted(link))",
                    "Uncial wants to remove the uncial command from \(folder)."
                )
            }
        }
    }

    private func perform(_ work: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch is Cancelled {
            // The user said no in the password dialog.
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    /// `command` through `do shell script … with administrator privileges` in osascript, a process of its
    /// own, as VS Code installs `code`: `NSAppleScript` would hold the main thread while the password
    /// dialog is up. Cancel there is AppleScript error -128.
    static func runWithOsascript(_ command: String, _ prompt: String) async throws {
        let script = "do shell script \(appleScriptString(command)) with prompt \(appleScriptString(prompt)) with administrator privileges"
        do {
            _ = try await ShellCommand.run("/usr/bin/osascript", ["-e", script])
        } catch let failure as ShellCommand.Failure where failure.output.contains("(-128)") {
            throw Cancelled()
        }
    }

    /// `text` as an AppleScript string literal.
    static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// `text` as one single-quoted shell word.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
