import Foundation

/// Name, version and copyright for the About tab, read from the bundle's Info.plist.
struct AppInfo {
    static let repositoryURL = URL(string: "https://github.com/vflame6/uncial")!
    /// The README's attribution line, as Markdown: the About tab and Uncial ▸ About Uncial render it
    /// with the handle linked.
    static let attribution = "Created by Maksim Radaev/[@vflame6](https://github.com/vflame6)"

    let name: String
    let version: String
    let copyright: String?

    init(info: [String: Any]) {
        name = info["CFBundleName"] as? String ?? "Uncial"
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        if let build = info["CFBundleVersion"] as? String, !build.isEmpty {
            version = "\(short) (\(build))"
        } else {
            version = short
        }
        let text = (info["NSHumanReadableCopyright"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        copyright = text.isEmpty ? nil : text
    }

    init(bundle: Bundle = .main) {
        self.init(info: bundle.infoDictionary ?? [:])
    }
}
