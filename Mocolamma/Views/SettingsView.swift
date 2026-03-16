import SwiftUI
import StoreKit
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
    @Environment(\.requestReview) var requestReview
    @State private var isReviewRequestDisabled: Bool = ReviewManager.shared.isReviewRequestDisabled
    
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
#if os(iOS)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Timeout")
                    Text("If responses take longer, such as when loading large models, increasing the timeout may help.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("API Timeout", selection: $apiTimeoutSelection) {
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
#elseif os(visionOS)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Timeout")
                    Text("If responses take longer, such as when loading large models, increasing the timeout may help.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("API Timeout", selection: $apiTimeoutSelection) {
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
#else
            Picker(selection: $apiTimeoutSelection) {
                Text("30 sec").tag(APITimeoutOption.seconds30)
                Text("1 min").tag(APITimeoutOption.minutes1)
                Text("5 min").tag(APITimeoutOption.minutes5)
                Text("Unlimited").tag(APITimeoutOption.unlimited)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Timeout")
                    Text("If responses take longer, such as when loading large models, increasing the timeout may help.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: apiTimeoutSelection) { _, newValue in
                APITimeoutManager.shared.set(option: newValue)
            }
#endif
        }
        
        Section("Permissions") {
#if !os(macOS)
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
#if os(visionOS)
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
#else
                            .buttonStyle(.borderless)
#endif
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
#if os(visionOS)
                    HStack(spacing: 16) {
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
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
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
#endif
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
                    Text("To allow local network access, go to System Settings → Privacy & Security → Local Network, and toggle \"Mocolamma\" on.\n\nClick or tap \"OK\" to open Privacy & Security settings.")
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
#endif
        }
        
        Section("App Store Features") {
#if os(macOS)
            Toggle(isOn: $isReviewRequestDisabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Disable Review Requests")
                    Text("Prevent the App Store review request screen from appearing periodically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: isReviewRequestDisabled) { _, newValue in
                ReviewManager.shared.isReviewRequestDisabled = newValue
            }
#elseif os(visionOS)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Disable Review Requests")
                    Text("Prevent the App Store review request screen from appearing periodically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("Disable Review Requests", isOn: $isReviewRequestDisabled)
                    .labelsHidden()
            }
            .onChange(of: isReviewRequestDisabled) { _, newValue in
                ReviewManager.shared.isReviewRequestDisabled = newValue
            }
#else
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Disable Review Requests")
                    Text("Prevent the App Store review request screen from appearing periodically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("Disable Review Requests", isOn: $isReviewRequestDisabled)
                    .labelsHidden()
            }
            .onChange(of: isReviewRequestDisabled) { _, newValue in
                ReviewManager.shared.isReviewRequestDisabled = newValue
            }
#endif
        }
        
#if DEBUG
        Section(header: Text(verbatim: "App Store Review Debug")) {
            HStack {
                Text(verbatim: "Total Actions")
                Spacer()
                Text(verbatim: "\(ReviewManager.shared.totalActionCount)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(verbatim: "Daily Actions")
                Spacer()
                Text(verbatim: "\(ReviewManager.shared.dailyActionCount)")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(verbatim: "Update Date")
                Spacer()
                Text(ReviewManager.shared.updateDate, format: .dateTime.year().month().day().hour().minute().second())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(verbatim: "Last Review Date")
                Spacer()
                if let lastDate = ReviewManager.shared.lastReviewRequestDate {
                    Text(lastDate, format: .dateTime.year().month().day().hour().minute().second())
                        .foregroundStyle(.secondary)
                } else {
                    Text(verbatim: "Never")
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack {
                Text(verbatim: "Add Action Counts")
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        ReviewManager.shared.debugAddActions(count: 1)
                    } label: {
                        Text(verbatim: "+1")
                    }
                    Button {
                        ReviewManager.shared.debugAddActions(count: 10)
                    } label: {
                        Text(verbatim: "+10")
                    }
                }
                .buttonStyle(.bordered)
            }
            
            Group {
                if horizontalSizeClass == .compact {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "Daily Action Count")
                        Button {
                            ReviewManager.shared.debugResetDailyCount()
                        } label: {
                            Text(verbatim: "Reset")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "All Review Stats")
                        Button {
                            ReviewManager.shared.debugResetStats()
                        } label: {
                            Text(verbatim: "Reset All")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "Last Review Data")
                        Button {
                            ReviewManager.shared.debugClearLastReviewDate()
                        } label: {
                            Text(verbatim: "Clear")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "Version Grace Period")
                        Button {
                            ReviewManager.shared.debugSkipUpdateGracePeriod()
                        } label: {
                            Text(verbatim: "Skip")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: "Review Prompt")
                        Button {
                            ReviewManager.shared.debugForceRequestReview(requestReviewAction: requestReview)
                        } label: {
                            Text(verbatim: "Force Request")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    HStack {
                        Text(verbatim: "Daily Action Count")
                        Spacer()
                        Button {
                            ReviewManager.shared.debugResetDailyCount()
                        } label: {
                            Text(verbatim: "Reset")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack {
                        Text(verbatim: "All Review Stats")
                        Spacer()
                        Button {
                            ReviewManager.shared.debugResetStats()
                        } label: {
                            Text(verbatim: "Reset All")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack {
                        Text(verbatim: "Last Review Data")
                        Spacer()
                        Button {
                            ReviewManager.shared.debugClearLastReviewDate()
                        } label: {
                            Text(verbatim: "Clear")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack {
                        Text(verbatim: "Version Grace Period")
                        Spacer()
                        Button {
                            ReviewManager.shared.debugSkipUpdateGracePeriod()
                        } label: {
                            Text(verbatim: "Skip")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    HStack {
                        Text(verbatim: "Review Prompt")
                        Spacer()
                        Button {
                            ReviewManager.shared.debugForceRequestReview(requestReviewAction: requestReview)
                        } label: {
                            Text(verbatim: "Force Request")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
#endif
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
