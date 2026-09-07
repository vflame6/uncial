import SwiftUI

/// Find bar for the rendered page (Read Only mode), styled after the text view's find bar.
struct PreviewFindBar: View {
    @Bindable var controller: PreviewFindController
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Find", text: $controller.query)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit { controller.find(backwards: false) }
                .frame(maxWidth: 320)
            if let status = controller.status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Button { controller.find(backwards: true) } label: { Image(systemName: "chevron.left") }
                    .help("Find Previous (\(AppShortcut.findPrevious.display))")
                Button { controller.find(backwards: false) } label: { Image(systemName: "chevron.right") }
                    .help("Find Next (\(AppShortcut.findNext.display))")
            }
            .disabled(controller.query.isEmpty)
            Button("Done") { controller.hide() }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onExitCommand { controller.hide() }
        .onAppear { isFocused = true }
        .onChange(of: controller.focusRequest) { isFocused = true }
    }
}
