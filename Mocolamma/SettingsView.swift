import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack {
            Text("Settings")
                .font(.title)
                .foregroundColor(.secondary)
            Text("No settings available yet")
                .foregroundColor(.secondary)
        }
        .frame(width: 500, height: 300)
    }
}

#Preview {
    SettingsView()
}
