import Foundation

/// Where a document's relative attachments (images, linked files) are looked for when nothing is at
/// the place a reference names: the attachments folder next to the document, then, with
/// `searchesParents`, every folder above the document's and its attachments folder, up to the
/// `boundary`. The walk repeats the reference's path relative to the document's folder under each
/// folder, so only references into that folder (a name, a sub-path) are searched; one that points
/// outside it (`../x`, `/etc/x`) is looked for where it points and nowhere else.
public struct AttachmentSearch: Equatable, Sendable {
    /// The topmost folder the parent walk visits.
    public enum Boundary: String, CaseIterable, Sendable {
        /// The user's home folder, included; a document outside it is searched in its own folder only.
        case home
        /// The root of the file system.
        case root
    }

    public static let defaultDirectoryName = "attachments"

    /// The folder tried next to the document and next to every parent visited: a name, a relative
    /// path or an absolute one; blank for none.
    public let directoryName: String
    /// Whether the folders above the document's are searched too.
    public let searchesParents: Bool
    public let boundary: Boundary

    public init(directoryName: String = AttachmentSearch.defaultDirectoryName, searchesParents: Bool = true, boundary: Boundary = .home) {
        self.directoryName = directoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.searchesParents = searchesParents
        self.boundary = boundary
    }

    /// Looks only where a reference points.
    public static let direct = AttachmentSearch(directoryName: "", searchesParents: false)

    /// The folders searched for the attachments of a document in `directory`, in order: `directory`
    /// itself, then its parents up to and including the boundary.
    public func directories(from directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var folder = Self.directoryURL(directory)
        var folders = [folder]
        guard searchesParents else { return folders }
        let homeComponents = Self.directoryURL(home).pathComponents
        guard boundary == .root || folder.pathComponents.starts(with: homeComponents) else { return folders }
        while !(boundary == .home && folder.pathComponents == homeComponents) {
            let parent = Self.directoryURL(folder.deletingLastPathComponent())
            guard parent.path != folder.path else { break }
            folder = parent
            folders.append(folder)
        }
        return folders
    }

    /// The places a reference resolved to `fileURL` from `directory` (the document's folder) is looked
    /// for, in order and without duplicates: `fileURL` first, then the relative path under each folder
    /// of `directories(from:home:)` and its attachments folder.
    public func candidates(for fileURL: URL, from directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let folder = Self.directoryURL(directory)
        let target = URL(fileURLWithPath: fileURL.path).standardizedFileURL
        let relative = Self.relativePath(of: target, from: folder)
        guard !relative.isEmpty, relative != "..", !relative.hasPrefix("../") else { return [target] }
        var seen: Set<String> = []
        var candidates: [URL] = []
        for base in directories(from: folder, home: home) {
            var places = [URL(fileURLWithPath: relative, relativeTo: base)]
            if !directoryName.isEmpty {
                let attachments = Self.directoryURL(URL(fileURLWithPath: directoryName, relativeTo: base))
                places.append(URL(fileURLWithPath: relative, relativeTo: attachments))
            }
            for place in places {
                let url = place.standardizedFileURL
                if seen.insert(url.path).inserted {
                    candidates.append(url)
                }
            }
        }
        return candidates
    }

    /// The first candidate that exists, nil when the reference is found nowhere.
    public func locate(
        _ fileURL: URL, from directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        candidates(for: fileURL, from: directory, home: home).first(where: exists)
    }

    /// `target`'s path relative to `directory`, climbing with `..` when it lies outside; empty for the
    /// directory itself.
    static func relativePath(of target: URL, from directory: URL) -> String {
        let targetComponents = target.standardizedFileURL.pathComponents
        let directoryComponents = directoryURL(directory).pathComponents
        let common = zip(targetComponents, directoryComponents).prefix { $0 == $1 }.count
        let ups = Array(repeating: "..", count: directoryComponents.count - common)
        return (ups + targetComponents[common...]).joined(separator: "/")
    }

    /// `url` as a standardized directory URL, so relative paths resolve inside it and not beside it.
    static func directoryURL(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
    }
}
