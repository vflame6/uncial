import Foundation

/// Settings the app shares with its sandboxed Quick Look extension through the App Group
/// container: a small plist, because `UserDefaults(suiteName:)` does not resolve to the group
/// container for an unsandboxed app.
public enum SharedSettings {
    /// Team-ID-prefixed so macOS needs no provisioning profile and shows no consent prompt.
    public static let groupIdentifier = "XWTLHG45H7.com.maksimradaev.uncial"
    static let fileName = "settings.plist"
    static let themeKey = "theme"

    /// The group container, or nil when the process lacks the entitlement.
    public static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    public static func readTheme(from directory: URL) -> Theme? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let raw = plist[themeKey] as? String else { return nil }
        return Theme(rawValue: raw)
    }

    public static func write(theme: Theme, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: [themeKey: theme.rawValue], format: .xml, options: 0)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }
}
