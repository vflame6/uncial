import SwiftUI

/// Window footer: the editing mode on the left, the document's line, word and character counts on the right.
struct StatusBarView: View {
    let mode: EditorMode
    let statistics: DocumentStatistics

    var body: some View {
        HStack(spacing: 16) {
            Label(mode.title, systemImage: mode.systemImage)
            Spacer(minLength: 0)
            Text(DocumentStatistics.phrase(statistics.lines, "line"))
            Text(DocumentStatistics.phrase(statistics.words, "word"))
            Text(DocumentStatistics.phrase(statistics.characters, "character"))
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
