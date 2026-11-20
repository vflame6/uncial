import Foundation

/// Where document windows were, so that a document opens in the place and at the size its window had,
/// and one that was never open here where the last window was. SwiftUI opens every document window at
/// the scene's default size in the middle of the screen, and macOS keeps frames only for the windows
/// left open at quit.
///
/// A place is a window's frame descriptor (`NSWindow.frameDescriptor`: the frame and its screen's), kept
/// per file path in the defaults, the most recent first, `limit` of them.
nonisolated final class DocumentWindowFrames {
    static let key = "documentWindowFrames"

    private struct Place {
        let path: String
        let frame: String
    }

    private let defaults: UserDefaults?
    private let limit: Int
    private var places: [Place]

    /// Without `defaults` nothing outlives the object: the unit tests run inside the app, under its
    /// bundle id, and must leave the user's window places alone.
    init(defaults: UserDefaults?, limit: Int = 100) {
        self.defaults = defaults
        self.limit = limit
        let stored = defaults?.array(forKey: Self.key) as? [[String: Any]] ?? []
        places = stored.compactMap { entry in
            guard let path = entry["path"] as? String, let frame = entry["frame"] as? String else { return nil }
            return Place(path: path, frame: frame)
        }
    }

    /// The place of `url`'s window, or of the last window when the document has none (or no file).
    func frame(for url: URL?) -> String? {
        ownFrame(for: url) ?? places.first?.frame
    }

    /// The place `url`'s own window had, if it had one.
    func ownFrame(for url: URL?) -> String? {
        guard let url else { return nil }
        let path = Self.path(of: url)
        return places.first { $0.path == path }?.frame
    }

    func remember(_ frame: String, for url: URL?) {
        let path = Self.path(of: url)
        places.removeAll { $0.path == path }
        places.insert(Place(path: path, frame: frame), at: 0)
        places = Array(places.prefix(limit))
        defaults?.set(places.map { ["path": $0.path, "frame": $0.frame] }, forKey: Self.key)
    }

    /// A document without a file has no place of its own; it still counts as the last window.
    private static func path(of url: URL?) -> String {
        url?.standardizedFileURL.path ?? ""
    }
}
