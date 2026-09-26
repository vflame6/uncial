import Foundation
import Testing
@testable import UncialCore

@MainActor final class ChangeCounter {
    private(set) var value = 0
    nonisolated init() {}
    func increment() { value += 1 }
}

@Suite struct FileWatcherTests {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uncial-watch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("doc.md")
        try Data("# one\n".utf8).write(to: file)
        return file
    }

    /// Starts a watcher, performs `mutation`, waits `settle`, returns how many callbacks fired.
    private func changes(on file: URL, settle: Duration, mutation: @escaping @Sendable () throws -> Void) async throws -> Int {
        let counter = ChangeCounter()
        let watcher = FileWatcher(url: file, debounce: 0.05) { counter.increment() }
        watcher.start()
        try await Task.sleep(for: .milliseconds(100))
        try mutation()
        try await Task.sleep(for: settle)
        watcher.stop()
        return await counter.value
    }

    @Test func firesOnInPlaceWrite() async throws {
        let file = try temporaryFile()
        let count = try await changes(on: file, settle: .milliseconds(400)) {
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("# two\n".utf8))
            try handle.close()
        }
        #expect(count == 1)
    }

    @Test func firesOnAtomicReplace() async throws {
        let file = try temporaryFile()
        let count = try await changes(on: file, settle: .milliseconds(600)) {
            let temporary = file.deletingLastPathComponent().appendingPathComponent("doc.md.tmp")
            try Data("# three\n".utf8).write(to: temporary)
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
        }
        #expect(count >= 1)
    }

    @Test func coalescesBursts() async throws {
        let file = try temporaryFile()
        let count = try await changes(on: file, settle: .milliseconds(400)) {
            let handle = try FileHandle(forWritingTo: file)
            for line in 0..<5 {
                try handle.seekToEnd()
                try handle.write(contentsOf: Data("line \(line)\n".utf8))
            }
            try handle.close()
        }
        #expect(count == 1)
    }

    /// A branch switch or a sync client can take the file away for seconds: the watcher keeps looking
    /// for it, reports it when it comes back, and follows its later changes.
    @Test func survivesALongAbsence() async throws {
        let file = try temporaryFile()
        let counter = ChangeCounter()
        let watcher = FileWatcher(url: file, debounce: 0.05) { counter.increment() }
        watcher.start()
        try await Task.sleep(for: .milliseconds(100))
        try FileManager.default.removeItem(at: file)
        try await Task.sleep(for: .milliseconds(1500))
        try Data("# back\n".utf8).write(to: file)
        try await Task.sleep(for: .milliseconds(2600))
        let afterReturn = await counter.value
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("# later\n".utf8))
        try handle.close()
        try await Task.sleep(for: .milliseconds(400))
        watcher.stop()
        #expect(afterReturn >= 1)
        #expect(await counter.value > afterReturn)
    }

    @Test func doesNotFireWithoutChanges() async throws {
        let file = try temporaryFile()
        let count = try await changes(on: file, settle: .milliseconds(300)) {}
        #expect(count == 0)
    }
}
