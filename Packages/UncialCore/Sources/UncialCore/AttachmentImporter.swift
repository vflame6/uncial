import Foundation
import UniformTypeIdentifiers

/// Puts a file pasted or dropped into a document where new attachments go and writes the Markdown
/// that references it. A file the document already reaches (inside its folder, in an attachments
/// folder the search covers, or any Markdown file) is linked where it is; every other file is copied
/// into the target folder under a free name (`name 2.ext`), unless an identical file is there already.
public struct AttachmentImporter: Sendable {
    /// Where a new attachment is put.
    public enum Destination: String, CaseIterable, Sendable {
        /// The attachments folder next to the document, created when missing.
        case attachmentsFolder
        /// The first attachments folder the search would look in that exists, from the document's
        /// folder upward; none existing, the one next to the document.
        case nearestAttachmentsFolder
        /// The document's own folder.
        case documentFolder
    }

    public let search: AttachmentSearch
    public let destination: Destination

    public init(search: AttachmentSearch, destination: Destination = .attachmentsFolder) {
        self.search = search
        self.destination = destination
    }

    /// The folder a new attachment of a document in `directory` goes to, not created here. With a
    /// blank attachments folder name every destination is the document's folder.
    public func targetDirectory(for directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let folder = AttachmentSearch.directoryURL(directory)
        guard destination != .documentFolder, !search.directoryName.isEmpty else { return folder }
        if destination == .nearestAttachmentsFolder {
            for base in search.directories(from: folder, home: home) {
                let candidate = Self.attachmentsFolder(in: base, named: search.directoryName)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return candidate
                }
            }
        }
        return Self.attachmentsFolder(in: folder, named: search.directoryName)
    }

    /// Whether a document in `directory` reaches `fileURL` without a copy: it lies inside the
    /// document's folder or in an attachments folder the search covers, or it is a Markdown file.
    public func reaches(_ fileURL: URL, from directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let folder = AttachmentSearch.directoryURL(directory)
        let target = URL(fileURLWithPath: fileURL.path).standardizedFileURL
        if MarkdownText.fileExtensions.contains(target.pathExtension.lowercased()) || Self.isInside(target, folder) {
            return true
        }
        guard !search.directoryName.isEmpty else { return false }
        return search.directories(from: folder, home: home).contains { base in
            Self.isInside(target, Self.attachmentsFolder(in: base, named: search.directoryName))
        }
    }

    /// Stores the file at `fileURL` for a document in `directory` and returns the file the document
    /// should reference: `fileURL` itself when the document reaches it, otherwise its copy in the
    /// target folder.
    public func store(fileAt fileURL: URL, for directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        let source = URL(fileURLWithPath: fileURL.path).standardizedFileURL
        if reaches(source, from: directory, home: home) { return source }
        let target = try createdTargetDirectory(for: directory, home: home)
        let destination = Self.freeURL(for: source.lastPathComponent, in: target) { existing in
            FileManager.default.contentsEqual(atPath: existing.path, andPath: source.path)
        }
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: source, to: destination)
        }
        return destination
    }

    /// Writes `data` as a file called `name` in the target folder (a free variant of the name when a
    /// different file has it, the existing file when it holds the same bytes) and returns it.
    public func store(_ data: Data, named name: String, for directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        let target = try createdTargetDirectory(for: directory, home: home)
        let destination = Self.freeURL(for: name, in: target) { existing in
            (try? Data(contentsOf: existing)) == data
        }
        if !FileManager.default.fileExists(atPath: destination.path) {
            try data.write(to: destination)
        }
        return destination
    }

    /// The Markdown that references `fileURL` from a document in `directory`: an image for picture
    /// files (the name without its extension as the text), a link otherwise.
    public static func markdown(for fileURL: URL, relativeTo directory: URL) -> String {
        let name = fileURL.lastPathComponent
        let isImage = UTType(filenameExtension: fileURL.pathExtension)?.conforms(to: .image) ?? false
        let text = (isImage ? (name as NSString).deletingPathExtension : name)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        return "\(isImage ? "!" : "")[\(text)](\(linkDestination(for: fileURL, relativeTo: directory)))"
    }

    /// The path from the document's folder to `fileURL` (`..` when it lies above), each component
    /// percent-encoded so spaces, parentheses, `#`, `%` and `<>` survive as a link destination.
    public static func linkDestination(for fileURL: URL, relativeTo directory: URL) -> String {
        AttachmentSearch.relativePath(of: fileURL, from: directory)
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: destinationAllowed) ?? String($0) }
            .joined(separator: "/")
    }

    /// A file name for pasted picture data, `pasted-image-20260922-153012.png`, in local time.
    public static func pastedImageName(extension ext: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "pasted-image-\(formatter.string(from: date)).\(ext)"
    }

    /// `folder/name`, or `folder/name 2.ext`, `… 3.ext` … while another file has the name; an
    /// existing file `sameAs` accepts is returned as it is.
    static func freeURL(for name: String, in folder: URL, sameAs: (URL) -> Bool) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            if sameAs(candidate) { return candidate }
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    private static let destinationAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()<>%")
        return allowed
    }()

    private func createdTargetDirectory(for directory: URL, home: URL) throws -> URL {
        let target = targetDirectory(for: directory, home: home)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    private static func attachmentsFolder(in base: URL, named name: String) -> URL {
        AttachmentSearch.directoryURL(URL(fileURLWithPath: name, relativeTo: AttachmentSearch.directoryURL(base)))
    }

    private static func isInside(_ file: URL, _ folder: URL) -> Bool {
        let fileComponents = file.standardizedFileURL.pathComponents
        let folderComponents = AttachmentSearch.directoryURL(folder).pathComponents
        return fileComponents.count > folderComponents.count && fileComponents.starts(with: folderComponents)
    }
}
