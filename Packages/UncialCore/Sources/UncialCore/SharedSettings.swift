import Foundation

/// Settings the app shares with its sandboxed Quick Look extensions through the App Group
/// container: a small plist, because `UserDefaults(suiteName:)` does not resolve to the group
/// container for an unsandboxed app. Holds the theme and whether remote content may load.
public enum SharedSettings {
    /// Team-ID-prefixed so macOS needs no provisioning profile and shows no consent prompt.
    public static let groupIdentifier = "XWTLHG45H7.com.maksimradaev.uncial"
    static let fileName = "settings.plist"
    static let themeKey = "theme"
    static let remoteContentKey = "remoteContent"

    /// The group container, or nil when the process lacks the entitlement.
    public static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    public static func readTheme(from directory: URL) -> Theme? {
        (read(from: directory)[themeKey] as? String).flatMap(Theme.init(rawValue:))
    }

    /// Whether the app lets documents load images and other files from the web; nil when never written.
    public static func readRemoteContent(from directory: URL) -> Bool? {
        read(from: directory)[remoteContentKey] as? Bool
    }

    public static func write(theme: Theme, remoteContent: Bool, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let plist: [String: Any] = [themeKey: theme.rawValue, remoteContentKey: remoteContent]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    private static func read(from directory: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [:] }
        return plist
    }
}
