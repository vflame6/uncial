import SwiftUI

/// First-run setup: the same settings as ⌘, plus Skip / Done.
struct WelcomeView: View {
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                Text("Welcome to Uncial")
                    .font(.title.weight(.semibold))
                Text("Take a minute to set things up. Everything here can be changed later in Settings (⌘,).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.horizontal, 32)

            GeneralSettingsView(settings: .shared, quickLook: .shared, defaultApp: .shared)
                .scrollDisabled(true)

            HStack {
                Button("Skip", action: finish)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done", action: finish)
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 520, height: 640)
    }
}
