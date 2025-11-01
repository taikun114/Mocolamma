import SwiftUI
#if os(macOS)
import AppKit
#endif
import Foundation

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) var openURL

    private var isOS26OrLater: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        } else {
            return false
        }
    }

    @State private var showingFeedbackMailAlert = false
    @State private var showingContributorsAlert = false
    @State private var showingBugReportAlert = false
    @State private var showingCommunityAlert = false
    @State private var showingGitHubStarAlert = false
    @State private var showingBuyMeACoffeeAlert = false
    @State private var showingPayPalAlert = false
    @State private var showingLicenseInfoModal = false

    var body: some View {
        #if os(macOS)
        aboutViewContent
            .frame(width: 550, height: 600)
        #else
        NavigationView {
            aboutViewContent
                .navigationTitle("About Mocolamma")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                        }
                    }
                }
        }
        #endif
    }

    private var aboutViewContent: some View {
        Form {
            Section(header: Text("About Mocolamma").font(.headline)) {
                HStack(alignment: .center, spacing: 20) {
                    if isOS26OrLater {
                        #if os(macOS)
                        Image(nsImage: NSImage(named: NSImage.Name("AppIconLiquidGlass")) ?? NSImage())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 96, height: 96)
                            .padding(8)
                            .padding(.trailing, -10)
                            .id(colorScheme)
                        #else
                        Image("AppIconLiquidGlass")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 96, height: 96)
                            .padding(8)
                            .padding(.trailing, -8)
                            .id(colorScheme)
                        #endif
                    } else {
                        #if os(macOS)
                        Image(nsImage: NSImage(named: NSImage.Name("AppIcon")) ?? NSImage())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 128, height: 128)
                            .padding(.trailing, -10)
                        #else
                        Image("AppIconLiquidGlass")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 96, height: 96)
                            .padding(.trailing, -4)
                            .id(colorScheme)
                        #endif
                    }

                    VStack(alignment: .leading) {
                        VStack(alignment: .leading) {
                            Text("Mocolamma")
                                #if os(macOS)
                                .font(.largeTitle)
                                #else
                                .font(.title2)
                                #endif
                                .fontWeight(.bold)
                            Group {
                                let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
                                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
                                Text("Version: \(short) (\(build))")
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                        .padding(.bottom, 8)
                        Text("Developed with Generative AI")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Copyright ©︎ 2025 Taiga Imaura")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                #if os(iOS)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mocolamma is an Open Source Application.")
                    Button(action: { showingLicenseInfoModal = true }) {
                        HStack {
                            Image(systemName: "doc")
                            Text("License Information")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $showingLicenseInfoModal) {
                        LicenseInfoModalView()
                    }
                }
                .padding(.vertical, 4)
                #else
                HStack(alignment: .center) {
                    Text("Mocolamma is an Open Source Application.")
                    Spacer()
                    Button(action: { showingLicenseInfoModal = true }) {
                        HStack {
                            Image(systemName: "doc")
                            Text("License Information")
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Show license information for this application and the libraries used.")
                    .sheet(isPresented: $showingLicenseInfoModal) {
                        LicenseInfoModalView()
                    }
                }
                #endif

                #if os(iOS)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contributors involved in the development")
                    Button(action: { showingContributorsAlert = true }) {
                        HStack {
                            Image(systemName: "person.2")
                            Text("Contributors")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .help("Open link to the GitHub contributors page.")
                    .alert("Open Link?", isPresented: $showingContributorsAlert) {
                        Button("Open") {
                            if let url = URL(string: "https://github.com/taikun114/Mocolamma/graphs/contributors") {
                                openURL(url)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to open the GitHub contributors page?")
                    }
                }
                .padding(.vertical, 4)
                #else
                HStack(alignment: .center) {
                    Text("Contributors involved in the development")
                    Spacer()
                    Button(action: { showingContributorsAlert = true }) {
                        HStack {
                            Image(systemName: "person.2")
                            Text("Contributors")
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Open link to the GitHub contributors page.")
                    .alert("Open Link?", isPresented: $showingContributorsAlert) {
                        Button("Open") {
                            if let url = URL(string: "https://github.com/taikun114/Mocolamma/graphs/contributors") {
                                openURL(url)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to open the GitHub contributors page?")
                    }
                }
                #endif
            }

            Section(header: Text("Support and Feedback").font(.headline)) {
                #if os(iOS)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Found a bug?")
                    Button(action: { showingBugReportAlert = true }) {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                            Text("Report a Bug")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .help("Open link to list of known bugs and report page.")
                    .alert("Open Link?", isPresented: $showingBugReportAlert) {
                        Button("Open") {
                            if let url = URL(string: "https://github.com/taikun114/Mocolamma/issues") {
                                openURL(url)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to open the Issue page on GitHub?")
                    }
                }
                .padding(.vertical, 4)
                #else
                HStack(alignment: .center) {
                    Text("Found a bug?")
                    Spacer()
                    Button(action: { showingBugReportAlert = true }) {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                            Text("Report a Bug")
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Open link to list of known bugs and report page.")
                    .alert("Open Link?", isPresented: $showingBugReportAlert) {
                        Button("Open") {
                            if let url = URL(string: "https://github.com/taikun114/Mocolamma/issues") {
                                openURL(url)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to open the Issue page on GitHub?")
                    }
                }
                #endif

                #if os(iOS)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Have an idea?")
                    Button(action: { showingFeedbackMailAlert = true }) {
                        HStack {
                            Image(systemName: "envelope")
                            Text("Send Feedback")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .help("Open the send feedback email window.")
                }
                .padding(.vertical, 4)
                #else
                HStack(alignment: .center) {
                    Text("Have an idea?")
                    Spacer()
                    Button(action: { showingFeedbackMailAlert = true }) {
                        HStack {
                            Image(systemName: "envelope")
                            Text("Send Feedback")
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Open the send feedback email window.")
                }
                #endif

                #if os(iOS)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ask questions and share your opinions")
                    Button(action: { showingCommunityAlert = true }) {
                        HStack {
                            Image(systemName: "ellipsis.bubble")
                            Text("Community")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .help("Open link to discussion page.")
                    .alert("Open Link?", isPresented: $showingCommunityAlert) {
                        Button("Open") {
                            if let url = URL(string: "https://github.com/taikun114/Mocolamma/discussions") {
                                openURL(url)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to open the Discussion page on GitHub?")
                    }
                }
                .padding(.vertical, 4)
                #else
                HStack(alignment: .center) {
                    Text("Ask questions and share your opinions")
                    Spacer()
                    Button(action: { showingCommunityAlert = true }) {
                        HStack {
                            Image(systemName: "ellipsis.bubble")
                            Text("Community")
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Open link to discussion page.")
                    .alert("Open Link?", isPresented: $showingCommunityAlert) {
                        Button("Open") {
                            if let url = URL(string: "https://github.com/taikun114/Mocolamma/discussions") {
                                openURL(url)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to open the Discussion page on GitHub?")
                    }
                }
                #endif
            }

            Section(header: Text("Support Developer").font(.headline)) {
                #if os(iOS)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading) {
                        Text("Give It a Star to GitHub Repository")
                            .font(.body)
                        Text("I would be so glad if you could give a star to the repository!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button(action: { showingGitHubStarAlert = true }) {
                        HStack {
                            Image(systemName: "star")
                            Text("Give It a Star")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .help("Open link to the GitHub repository page.")
                    .alert("Open Link?", isPresented: $showingGitHubStarAlert) {
                        Button("Open") {
                            if let url = URL(string: "https://github.com/taikun114/Mocolamma") {
                                openURL(url)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to open the GitHub repository page?")
                    }
                }
                .padding(.vertical, 4)
                #else
                HStack(alignment: .center) {
                    VStack(alignment: .leading) {
                        Text("Give It a Star to GitHub Repository")
                            .font(.body)
                        Text("I would be so glad if you could give a star to the repository!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { showingGitHubStarAlert = true }) {
                        HStack {
                            Image(systemName: "star")
                            Text("Give It a Star")
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Open link to the GitHub repository page.")
                    .alert("Open Link?", isPresented: $showingGitHubStarAlert) {
                        Button("Open") {
                            if let url = URL(string: "https://github.com/taikun114/Mocolamma") {
                                openURL(url)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to open the GitHub repository page?")
                    }
                }
                #endif

                #if os(iOS)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading) {
                        Text("Buy Me Green Tea")
                            .font(.body)
                        Text("You can support me at Buy Me a Coffee from the price of a cup of green tea.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button(action: { showingBuyMeACoffeeAlert = true }) {
                        HStack {
                            Image(systemName: "cup.and.saucer")
                            Text("Buy Green Tea")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .help("Open link to the Buy Me a Coffee page.")
                    .alert("Open Link?", isPresented: $showingBuyMeACoffeeAlert) {
                        Button("Open") {
                            if let url = URL(string: "https://www.buymeacoffee.com/i_am_taikun") {
                                openURL(url)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to open the Buy Me a Coffee page?")
                    }
                }
                .padding(.vertical, 4)
                #else
                HStack(alignment: .center) {
                    VStack(alignment: .leading) {
                        Text("Buy Me Green Tea")
                            .font(.body)
                        Text("You can support me at Buy Me a Coffee from the price of a cup of green tea.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { showingBuyMeACoffeeAlert = true }) {
                        HStack {
                            Image(systemName: "cup.and.saucer")
                            Text("Buy Green Tea")
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Open link to the Buy Me a Coffee page.")
                    .alert("Open Link?", isPresented: $showingBuyMeACoffeeAlert) {
                        Button("Open") {
                            if let url = URL(string: "https://www.buymeacoffee.com/i_am_taikun") {
                                openURL(url)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to open the Buy Me a Coffee page?")
                    }
                }
                #endif

                #if os(iOS)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading) {
                        Text("Donate at PayPal")
                            .font(.body)
                        Text("You can also donate directly at PayPal.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button(action: { showingPayPalAlert = true }) {
                        HStack {
                            Image(systemName: "creditcard")
                            Text("Donate at PayPal")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .help("Open link to the PayPal.Me.")
                    .alert("Open Link?", isPresented: $showingPayPalAlert) {
                        Button("Open") {
                            if let url = URL(string: "https://paypal.me/taikun114") {
                                openURL(url)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to open the PayPal.Me page?")
                    }
                }
                .padding(.vertical, 4)
                #else
                HStack(alignment: .center) {
                    VStack(alignment: .leading) {
                        Text("Donate at PayPal")
                            .font(.body)
                        Text("You can also donate directly at PayPal.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { showingPayPalAlert = true }) {
                        HStack {
                            Image(systemName: "creditcard")
                            Text("Donate at PayPal")
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Open link to the PayPal.Me.")
                    .alert("Open Link?", isPresented: $showingPayPalAlert) {
                        Button("Open") {
                            if let url = URL(string: "https://paypal.me/taikun114") {
                                openURL(url)
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to open the PayPal.Me page?")
                    }
                }
                #endif
            }
        }
        .formStyle(.grouped)
        .alert("Open the Send Email window?", isPresented: $showingFeedbackMailAlert) {
            Button("Open") {
                if let url = URL(string: "mailto:contact.taikun@gmail.com?subject=\(formattedFeedbackSubject())&body=\(formattedFeedbackBody())") {
                    openURL(url)
                }
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to open the send feedback email window?")
        }
    }

    private func formattedFeedbackSubject() -> String {
        let appName = "Mocolamma"
        let languageCode = Locale.current.language.languageCode?.identifier
        let subjectPrefix: String = (languageCode == "ja") ? "\(appName)のフィードバック: " : "\(appName) Feedback: "
        return subjectPrefix.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }

    private func formattedFeedbackBody() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
        let appBuildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        let cpuArchitecture = "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        let cpuArchitecture = "Intel (x86_64)"
        #else
        let cpuArchitecture = "N/A"
        #endif

        let osType: String
        #if os(iOS)
        if ProcessInfo.processInfo.isiOSAppOnMac {
            osType = "macOS (iPad App)"
        } else if UIDevice.current.userInterfaceIdiom == .pad {
            osType = "iPadOS"
        } else if UIDevice.current.userInterfaceIdiom == .phone {
            osType = "iOS"
        } else if UIDevice.current.userInterfaceIdiom == .vision {
            osType = "visionOS (iPad App)"
        } else {
            osType = "iOS / iPadOS (Unknown)"
        }
        #elseif os(macOS)
        osType = "macOS"
        #else
        osType = "Unknown"
        #endif

        let languageCode = Locale.current.language.languageCode?.identifier
        let body: String
        if languageCode == "ja" {
            body = """
            フィードバック内容を具体的に説明してください:


            システム情報:

            ・OSの種類
            　\(osType)

            ・OSバージョン
            　\(osVersion)

            ・アプリ
            　バージョン\(appVersion)（ビルド\(appBuildNumber)）
            """
        } else {
            body = """
            Please describe your feedback in detail:


            System Information:

            ・OS Type
            　\(osType)

            ・OS Version
            　\(osVersion)

            ・App
            　Version \(appVersion) (Build \(appBuildNumber))
            """
        }
        return body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }
}

#Preview {
    AboutView()
}
