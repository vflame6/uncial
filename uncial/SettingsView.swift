import SwiftUI

struct SettingsView: View {
    var body: some View {
        SettingsForm(settings: AppSettings.shared, quickLook: .shared, defaultApp: .shared)
            .frame(width: 480)
    }
}
