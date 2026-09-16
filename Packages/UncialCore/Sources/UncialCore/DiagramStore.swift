import CryptoKit
import Foundation

/// Diagrams mermaid.js drew in the app, kept in the App Group container so the sandboxed Quick Look
/// extension, in which WebKit cannot launch its helper processes, shows them too: one plist per
/// theme and source, named by a hash of both, the newest `limit` kept. A document the app never
/// rendered has none, and its Quick Look preview keeps those fences as code.
public struct DiagramStore: Sendable {
    public static let limit = 400
    private static let lightKey = "light"
    private static let darkKey = "dark"
    private static let sourceKey = "source"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The store in the App Group container, or nil when this process lacks the entitlement.
    public static var shared: DiagramStore? {
        SharedSettings.containerURL().map { DiagramStore(directory: $0.appendingPathComponent("diagrams", isDirectory: true)) }
    }

    /// Writes every diagram (best effort) and drops the oldest files beyond `limit`.
    public func save(_ diagrams: [String: PreRenderedDiagram], theme: Theme) {
        guard !diagrams.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (source, diagram) in diagrams {
            let plist: [String: String] = [Self.sourceKey: source, Self.lightKey: diagram.light, Self.darkKey: diagram.dark]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else { continue }
            try? data.write(to: url(for: source, theme: theme), options: .atomic)
        }
        prune()
    }

    /// The stored diagrams among `sources`, keyed by source.
    public func diagrams(for sources: [String], theme: Theme) -> [String: PreRenderedDiagram] {
        var result: [String: PreRenderedDiagram] = [:]
        for source in sources {
            guard let data = try? Data(contentsOf: url(for: source, theme: theme)),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
                  plist[Self.sourceKey] == source, let light = plist[Self.lightKey], let dark = plist[Self.darkKey] else { continue }
            result[source] = PreRenderedDiagram(light: light, dark: dark)
        }
        return result
    }

    func url(for source: String, theme: Theme) -> URL {
        directory.appendingPathComponent(Self.name(for: source, theme: theme)).appendingPathExtension("plist")
    }

    static func name(for source: String, theme: Theme) -> String {
        let digest = SHA256.hash(data: Data((theme.rawValue + "\n" + source).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func prune() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)),
              files.count > Self.limit else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: keys))?.contentModificationDate ?? .distantPast) }
        for (file, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - Self.limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
