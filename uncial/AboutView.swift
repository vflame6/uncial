import SwiftUI

/// About tab: icon, version, what renders the Markdown, where the source lives.
struct AboutView: View {
    private let info = AppInfo()

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(info.name)
                .font(.title.weight(.semibold))
            Text("Version \(info.version)")
                .foregroundStyle(.secondary)
            Text("A native Markdown reader and editor for macOS, with Quick Look preview and thumbnail extensions.")
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Text("GitHub-flavored Markdown by cmark-gfm, math by KaTeX, diagrams by beautiful-mermaid.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link("View on GitHub", destination: AppInfo.repositoryURL)
                .padding(.top, 6)
            if let copyright = info.copyright {
                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
