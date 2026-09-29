import Foundation
import Testing
import UncialCore
@testable import Uncial

/// The `uncial` shell command inside the app: the test host is Uncial.app, so its copy is the one that
/// ships. `/usr/bin/open` is replaced by a stand-in that records its arguments, so nothing opens.
@Suite(.serialized) final class UncialCommandTests {
    private let folder: URL
    private let log: URL
    private let fakeOpen: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-command-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        folder = URL(fileURLWithPath: Self.canonical(base.path), isDirectory: true)
        log = folder.appendingPathComponent("open.log")
        fakeOpen = folder.appendingPathComponent("fake-open")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$UNCIAL_TEST_LOG\"\n".write(to: fakeOpen, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeOpen.path)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private var script: URL { Bundle.main.url(forResource: "uncial", withExtension: nil)! }
    private var app: String { Self.canonical(Bundle.main.bundlePath) }

    /// `path` with every symbolic link resolved, as `realpath` and `pwd -P` write it (Foundation's
    /// `resolvingSymlinksInPath` drops a leading /private instead).
    private static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private struct Run {
        let status: Int32
        let output: String
        let errors: String
        /// The arguments `open` got; nil when it did not run.
        let opened: [String]?
    }

    private func run(_ arguments: [String], via command: URL? = nil) throws -> Run {
        try? FileManager.default.removeItem(at: log)
        let process = Process()
        process.executableURL = command ?? script
        process.arguments = arguments
        process.currentDirectoryURL = folder
        var environment = ProcessInfo.processInfo.environment
        environment["UNCIAL_OPEN"] = fakeOpen.path
        environment["UNCIAL_TEST_LOG"] = log.path
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let opened = (try? String(contentsOf: log, encoding: .utf8)).map {
            $0.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        }
        return Run(status: process.terminationStatus,
                   output: String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                   errors: String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                   opened: opened)
    }

    @Test func opensTheAppAlone() throws {
        let run = try run([])
        #expect(run.status == 0)
        #expect(run.opened == ["-a", app])
    }

    /// Relative names become absolute paths, spaces and quotes intact, all in one `open`.
    @Test func opensFilesByAbsolutePath() throws {
        let names = ["a.md", "b b.md", "it's \"odd\".md"]
        for name in names {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        let run = try run(names)
        #expect(run.status == 0)
        #expect(run.opened == ["-a", app] + names.map { folder.appendingPathComponent($0).path })
    }

    /// A missing note is created empty and opened; a name that is no note, a missing folder and a
    /// folder are refused with a line each, and the rest still open.
    @Test func createsMissingNotesAndRefusesTheRest() throws {
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("kept.md"))
        let run = try run(["new.MD", "ideas", "nope/idea.md", "sub", "kept.md"])
        #expect(run.status == 1)
        #expect(run.opened == ["-a", app, folder.appendingPathComponent("new.MD").path, folder.appendingPathComponent("kept.md").path])
        #expect(try Data(contentsOf: folder.appendingPathComponent("new.MD")).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("ideas").path))
        #expect(run.errors.split(separator: "\n") == ["uncial: ideas: not a Markdown file name", "uncial: nope: No such directory", "uncial: sub: Is a directory"])
    }

    /// Nothing left to open: `open` does not run at all.
    @Test func opensNothingWhenEveryFileIsRefused() throws {
        let run = try run(["ideas"])
        #expect(run.status == 1 && run.opened == nil)
    }

    /// Homebrew and Settings link the command from elsewhere; it still opens the app it lives in.
    @Test func worksThroughASymlink() throws {
        let link = folder.appendingPathComponent("bin/uncial")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: script)
        let run = try run([], via: link)
        #expect(run.opened == ["-a", app])
    }

    @Test func options() throws {
        let help = try run(["-h"])
        #expect(help.status == 0 && help.output.hasPrefix("usage: uncial") && help.opened == nil)
        let unknown = try run(["-x"])
        #expect(unknown.status == 2 && unknown.errors.hasPrefix("uncial: unknown option -x") && unknown.opened == nil)
        let dashed = try run(["--", "-dash.md"])
        #expect(dashed.status == 0 && dashed.opened == ["-a", app, folder.appendingPathComponent("-dash.md").path])
    }

    /// The script's own list of Markdown extensions is the app's.
    @Test func knowsTheAppsMarkdownExtensions() throws {
        let text = try String(contentsOf: script, encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first { $0.hasPrefix("markdown_extensions=") })
        let names = line.dropFirst("markdown_extensions=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"")).split(separator: " ").map(String.init)
        #expect(Set(names) == MarkdownText.fileExtensions)
    }
}
