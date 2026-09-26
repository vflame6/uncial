import SwiftUI

/// About tab: icon, version, what renders the Markdown, who made it, where the source lives.
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
            // The window sizes itself to its content's ideal size, where these would get one line and
            // be cut off; they take the lines they need at the window's width instead.
            Text("A native Markdown reader and editor for macOS, with Quick Look preview and thumbnail extensions.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Text("GitHub-flavored Markdown by cmark-gfm, math by KaTeX, diagrams by beautiful-mermaid and mermaid.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text((try? AttributedString(markdown: AppInfo.attribution)) ?? AttributedString(AppInfo.attribution))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Link("View on GitHub", destination: AppInfo.repositoryURL)
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
