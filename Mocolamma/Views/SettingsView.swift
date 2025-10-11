import SwiftUI
#if os(macOS)
import ServiceManagement
#endif
#if os(macOS)
import AppKit
#endif
import Network

struct SettingsView: View {
    @State private var launchAtLogin: Bool = false
    @State private var apiTimeoutSelection: APITimeoutOption = APITimeoutManager.shared.currentOption
    @StateObject private var localNetworkChecker = LocalNetworkPermissionChecker()
    @State private var showingInstructions: Bool = false
    @State private var showingAbout: Bool = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
    
    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 400, height: 400)
        #else
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAbout = true }) {
                    Image(systemName: "info.circle")
                }
                .sheet(isPresented: $showingAbout) {
                    AboutView()
                }
            }
        }
        #endif
        .onAppear {
            #if os(macOS)
            launchAtLogin = LoginItemManager.shared.isEnabled
            #endif
            apiTimeoutSelection = APITimeoutManager.shared.currentOption
            localNetworkChecker.refresh()
        }
    }
    
    @ViewBuilder
    private var content: some View {
        Section("General") {
            #if os(macOS)
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItemManager.shared.setEnabled(newValue)
                }
            #endif
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Timeout")
                    Text("If responses take longer, such as when loading large models, increasing the timeout may help.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: $apiTimeoutSelection) {
                    Text("30 sec").tag(APITimeoutOption.seconds30)
                    Text("1 min").tag(APITimeoutOption.minutes1)
                    Text("5 min").tag(APITimeoutOption.minutes5)
                    Text("Unlimited").tag(APITimeoutOption.unlimited)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: apiTimeoutSelection) { _, newValue in
                    APITimeoutManager.shared.set(option: newValue)
                }
            }
        }
        
        Section("Permissions") {
            #if os(iOS)
            Group {
                if horizontalSizeClass == .compact { // iPhone縦向き、またはiPad狭い分割画面
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            if differentiateWithoutColor {
                                Image(systemName: localNetworkChecker.isAllowed ? "checkmark" : "xmark")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 10, height: 10)
                                    .foregroundStyle(localNetworkChecker.isAllowed ? .green : .red)
                                    .fontWeight(.bold)
                            } else {
                                Circle()
                                    .fill(localNetworkChecker.isAllowed ? Color.green : Color.red)
                                    .frame(width: 10, height: 10)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Local Network Access")
                                Text("Permission is required to connect to Ollama servers on the same network.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: { localNetworkChecker.refresh() }) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Refresh status")
                        }
                        Button(action: { showingInstructions = true }) {
                            HStack {
                                Image(systemName: localNetworkChecker.isAllowed ? "checkmark" : "gearshape.fill")
                                Text(localNetworkChecker.isAllowed ? "Allowed" : "How to Set Up")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(localNetworkChecker.isAllowed)
                        .help(localNetworkChecker.isAllowed ? "Local network permission is granted." : "How to set up local network permission.")
                        .alert("How to Set Up", isPresented: $showingInstructions) {
                            Button("OK") { }
                        } message: {
                            Text("To allow local network access, go to Settings → Privacy & Security → Local Network, and toggle \"Mocolamma\" on.")
                        }
                    }
                } else { // .regular - iPhone横向き、iPad全画面表示または広い分割画面
                    HStack {
                        if differentiateWithoutColor {
                            Image(systemName: localNetworkChecker.isAllowed ? "checkmark" : "xmark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 10, height: 10)
                                .foregroundStyle(localNetworkChecker.isAllowed ? .green : .red)
                                .fontWeight(.bold)
                        } else {
                            Circle()
                                .fill(localNetworkChecker.isAllowed ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                        }
                        VStack(alignment: .leading) {
                            Text("Local Network Access")
                            Text("Permission is required to connect to Ollama servers on the same network.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(action: { localNetworkChecker.refresh() }) { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Refresh status")
                        Button(action: { showingInstructions = true }) {
                            HStack {
                                Image(systemName: localNetworkChecker.isAllowed ? "checkmark" : "gearshape.fill")
                                Text(localNetworkChecker.isAllowed ? "Allowed" : "How to Set Up")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(localNetworkChecker.isAllowed)
                        .help(localNetworkChecker.isAllowed ? "Local network permission is granted." : "How to set up local network permission.")
                        .alert("How to Set Up", isPresented: $showingInstructions) {
                            Button("OK") { }
                        } message: {
                            Text("To allow local network access, go to Settings → Privacy & Security → Local Network, and toggle \"Mocolamma\" on.")
                        }
                    }
                }
            }
            #else
            HStack {
                if differentiateWithoutColor {
                    Image(systemName: localNetworkChecker.isAllowed ? "checkmark" : "xmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 10, height: 10)
                        .foregroundStyle(localNetworkChecker.isAllowed ? .green : .red)
                        .fontWeight(.bold)
                } else {
                    Circle()
                        .fill(localNetworkChecker.isAllowed ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                }
                VStack(alignment: .leading) {
                    Text("Local Network Access")
                    Text("Permission is required to connect to Ollama servers on the same network.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { localNetworkChecker.refresh() }) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh status")
                Button(action: { showingInstructions = true }) {
                    HStack {
                        Image(systemName: localNetworkChecker.isAllowed ? "checkmark" : "gearshape.fill")
                        Text(localNetworkChecker.isAllowed ? "Allowed" : "Open Settings")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(localNetworkChecker.isAllowed)
                .help(localNetworkChecker.isAllowed ? "Local network permission is granted." : "How to set up local network permission.")
                .alert("How to Set Up", isPresented: $showingInstructions) {
                    Button("OK") {
                        localNetworkChecker.openSystemPreferences()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("To allow local network access, go to System Settings → Privacy & Security → Local Network, and toggle \"Mocolamma\" on.\n\nClick \"OK\" to open Privacy & Security settings.")
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            #endif
        }
    }
}
#if os(macOS)
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
#endif

final class LocalNetworkPermissionChecker: ObservableObject {
    @Published var isAllowed: Bool = false
    
    private let authorizer = LocalNetworkAuthorization()
    
    func refresh() {
        Task { @MainActor in
            let granted = await authorizer.requestAuthorization()
            self.isAllowed = granted
        }
    }
    
    func openSystemPreferences() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}

private class LocalNetworkAuthorization: NSObject, NetServiceDelegate {
    private var browser: NWBrowser?
    private var netService: NetService?
    private var completion: ((Bool) -> Void)?
    
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            self.requestAuthorization { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    private func requestAuthorization(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        let browser = NWBrowser(for: .bonjour(type: "_bonjour._tcp", domain: nil), using: parameters)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .failed:
                break
            case .ready:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let completion = self.completion {
                        self.reset()
                        completion(true)
                        self.completion = nil
                    }
                }
            case .waiting(_):
                self.reset()
                self.completion?(false)
                self.completion = nil
            default:
                break
            }
        }
        
        self.netService = NetService(domain: "local.", type:"_lnp._tcp.", name: "LocalNetworkPrivacy", port: 11434)
        
        self.browser?.start(queue: .main)
        self.netService?.publish()
    }
    
    private func reset() {
        self.browser?.cancel()
        self.browser = nil
        self.netService?.stop()
        self.netService = nil
    }
}

#Preview {
    SettingsView()
}
