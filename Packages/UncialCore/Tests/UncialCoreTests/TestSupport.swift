import Foundation

/// A folder of its own in the temporary directory, deleted with the value. A suite that works with
/// files keeps one as a stored property: every test gets a fresh folder and leaves nothing behind.
final class TemporaryDirectory: Sendable {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("uncial-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// `path` inside the folder; nothing is created.
    func url(_ path: String, isDirectory: Bool = false) -> URL {
        url.appendingPathComponent(path, isDirectory: isDirectory)
    }

    /// Creates the folder at `path` and the folders on the way.
    @discardableResult
    func folder(_ path: String) throws -> URL {
        let folder = url(path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes `contents` to the file at `path`, creating the folders on the way.
    @discardableResult
    func file(_ path: String, _ contents: Data) throws -> URL {
        let file = url(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file)
        return file
    }

    @discardableResult
    func file(_ path: String, _ contents: String = "") throws -> URL {
        try file(path, Data(contents.utf8))
    }
}
