import Foundation
import Testing
@testable import Uncial

@MainActor
@Suite struct CommandLineToolManagerTests {
    private nonisolated static let script = "/Applications/Uncial.app/Contents/Resources/uncial"

    /// An in-memory file system: items by path, the folders the user may write, what was done.
    private final class Disk {
        var items: [String: CommandLineFileSystem.Item] = [:]
        var existing: Set<String> = []
        var writable: Set<String> = []
        var created: [String] = []
        var removed: [String] = []

        var fileSystem: CommandLineFileSystem {
            CommandLineFileSystem(
                item: { self.items[$0] ?? .nothing },
                exists: { self.existing.contains($0) },
                isWritableDirectory: { self.writable.contains($0) },
                createLink: { path, destination in
                    self.items[path] = .link(to: destination)
                    self.created.append("\(path) -> \(destination)")
                },
                remove: { path in
                    self.items[path] = nil
                    self.removed.append(path)
                }
            )
        }
    }

    /// The administrator commands asked for; `cancels` answers the password dialog with Cancel.
    private final class Administrator {
        var commands: [String] = []
        var cancels = false
    }

    private func manager(_ disk: Disk, administrator: Administrator = Administrator(), script: String = Self.script) -> CommandLineToolManager {
        let manager = CommandLineToolManager()
        manager.scriptPath = script
        manager.fileSystem = disk.fileSystem
        manager.runAsAdministrator = { command, _ in
            if administrator.cancels { throw CommandLineToolManager.Cancelled() }
            administrator.commands.append(command)
        }
        return manager
    }

    @Test func readsWhereTheCommandStands() {
        let disk = Disk()
        let tool = manager(disk)
        tool.refresh()
        #expect(tool.state == .notInstalled && !tool.state.isAvailable)

        disk.items["/usr/local/bin/uncial"] = .link(to: Self.script)
        tool.refresh()
        #expect(tool.state == .installed(folder: "/usr/local/bin") && tool.state.isAvailable)

        disk.items["/usr/local/bin/uncial"] = .link(to: "/Users/me/src/uncial/build/Build/Products/Debug/Uncial.app/Contents/Resources/uncial")
        tool.refresh()
        #expect(tool.state == .otherCopy(app: "/Users/me/src/uncial/build/Build/Products/Debug/Uncial.app"))

        disk.items["/usr/local/bin/uncial"] = .file
        tool.refresh()
        #expect(tool.state == .taken(path: "/usr/local/bin/uncial"))

        // Homebrew's link, relative as `ln -s` may write it, next to the cask's record.
        disk.items["/usr/local/bin/uncial"] = nil
        disk.items["/opt/homebrew/bin/uncial"] = .link(to: "../../../Applications/Uncial.app/Contents/Resources/uncial")
        disk.existing.insert("/opt/homebrew/Caskroom/uncial")
        tool.refresh()
        #expect(tool.state == .homebrew && tool.state.isAvailable)
    }

    /// Install links the script itself when the folder is the user's, and asks for an administrator when
    /// not, every path one shell word.
    @Test func installsDirectlyOrAsAdministrator() async {
        let disk = Disk()
        disk.writable.insert("/usr/local/bin")
        let tool = manager(disk)
        await tool.install()
        #expect(disk.created == ["/usr/local/bin/uncial -> \(Self.script)"])
        #expect(tool.state == .installed(folder: "/usr/local/bin") && tool.errorMessage == nil)

        let locked = Disk()
        let administrator = Administrator()
        let quoted = manager(locked, administrator: administrator, script: "/Applications/My Apps/Un'cial.app/Contents/Resources/uncial")
        await quoted.install()
        #expect(administrator.commands == [#"/bin/mkdir -p '/usr/local/bin' && /bin/ln -sfh '/Applications/My Apps/Un'\''cial.app/Contents/Resources/uncial' '/usr/local/bin/uncial'"#])
        #expect(locked.created.isEmpty && quoted.errorMessage == nil)
    }

    /// Cancel in the password dialog changes nothing and says nothing.
    @Test func cancellingThePasswordIsNoError() async {
        let administrator = Administrator()
        administrator.cancels = true
        let tool = manager(Disk(), administrator: administrator)
        await tool.install()
        #expect(tool.errorMessage == nil && tool.state == .notInstalled && !tool.isBusy)
    }

    /// Nothing replaces a file that is not Uncial's, nothing links a translocated copy, and Homebrew's
    /// link stays Homebrew's.
    @Test func leavesOtherFilesAlone() async {
        let taken = Disk()
        taken.writable.insert("/usr/local/bin")
        taken.items["/usr/local/bin/uncial"] = .file
        await manager(taken).install()
        #expect(taken.created.isEmpty && taken.removed.isEmpty)

        let moved = Disk()
        moved.writable.insert("/usr/local/bin")
        let translocated = manager(moved, script: "/private/var/folders/x/T/AppTranslocation/ABC/d/Uncial.app/Contents/Resources/uncial")
        #expect(translocated.isTranslocated)
        await translocated.install()
        #expect(moved.created.isEmpty)

        let brewed = Disk()
        brewed.writable.insert("/opt/homebrew/bin")
        brewed.items["/opt/homebrew/bin/uncial"] = .link(to: Self.script)
        brewed.existing.insert("/opt/homebrew/Caskroom/uncial")
        await manager(brewed).remove()
        #expect(brewed.removed.isEmpty)
    }

    /// Remove takes away the link Install made, as an administrator when the folder is not the user's.
    @Test func removesItsOwnLink() async {
        let disk = Disk()
        disk.writable.insert("/usr/local/bin")
        disk.items["/usr/local/bin/uncial"] = .link(to: Self.script)
        let tool = manager(disk)
        await tool.remove()
        #expect(disk.removed == ["/usr/local/bin/uncial"] && tool.state == .notInstalled)

        let locked = Disk()
        locked.items["/usr/local/bin/uncial"] = .link(to: Self.script)
        let administrator = Administrator()
        await manager(locked, administrator: administrator).remove()
        #expect(administrator.commands == ["/bin/test -L '/usr/local/bin/uncial' && /bin/rm '/usr/local/bin/uncial'"])
    }

    @Test func quotesForAppleScriptAndTheShell() {
        #expect(CommandLineToolManager.appleScriptString(#"say "hi" \ bye"#) == #""say \"hi\" \\ bye""#)
        #expect(CommandLineToolManager.shellQuoted("it's") == #"'it'\''s'"#)
    }
}
