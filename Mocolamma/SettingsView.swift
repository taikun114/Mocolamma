import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var launchAtLogin: Bool = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItemManager.shared.setEnabled(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 300)
        .onAppear {
            launchAtLogin = LoginItemManager.shared.isEnabled
        }
    }
}

final class LoginItemManager {
    static let shared = LoginItemManager()
    private init() {}

    private let helperIdentifier = Bundle.main.bundleIdentifier ?? ""

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[LoginItemManager] Failed to set login item: \(error.localizedDescription)")
        }
    }
}

#Preview {
    SettingsView()
}
