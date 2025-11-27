import SwiftUI

struct LicenseTextView: View {
    let licenseText: String
    let licenseLink: String?
    let licenseTitle: String
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @State private var isTextWrapped: Bool = true
    @State private var showingLicenseLinkAlert = false
    
    var body: some View {
#if os(macOS)
        licenseTextViewContent
            .frame(width: 700, height: 500)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { // 下部にオーバーレイとしてVisualEffectViewとボタンを配置
                ZStack(alignment: .center) {
                    if #available(macOS 26, *) {
                        Color.clear
                            .glassEffect()
                            .edgesIgnoringSafeArea(.horizontal)
                    } else {
                        VisualEffectView(material: .headerView, blendingMode: .withinWindow)
                            .edgesIgnoringSafeArea(.horizontal)
                    }
                    HStack {
                        if let link = licenseLink, let url = URL(string: link) {
                            Button {
                                showingLicenseLinkAlert = true
                            } label: {
                                Label("Open License Page", systemImage: "paperclip")
                            }
                            .controlSize(.large)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        
                        Spacer()
                        
                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .frame(height: 60) // オーバーレイの固定高さ
            }
            .alert("Open License Page?", isPresented: $showingLicenseLinkAlert) {
                Button("Open") {
                    if let link = licenseLink, let url = URL(string: link) {
                        openURL(url)
                    }
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to open the page with license information?")
            }
#else
        NavigationView {
            licenseTextViewContent
                .navigationTitle("License")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if let link = licenseLink, let url = URL(string: link) {
                            Button(action: { showingLicenseLinkAlert = true }) {
                                Image(systemName: "paperclip")
                            }
                        }
                    }
                    // iOS 26.0 以降の場合のみ ToolbarSpacer を追加
                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .primaryAction) // ToolbarItem の外に配置
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            isTextWrapped.toggle()
                            print("isTextWrapped: \(isTextWrapped)")
                        }) {
                            Label("Toggle Text Wrapping", systemImage: "arrow.up.and.down.text.horizontal")
                        }
                    }
                }
                .modifier(NavSubtitleIfAvailable(subtitle: Text(licenseTitle)))
                .alert("Open License Page?", isPresented: $showingLicenseLinkAlert) {
                    Button("Open") {
                        if let link = licenseLink, let url = URL(string: link) {
                            openURL(url)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Are you sure you want to open the page with license information?")
                }
        }
        .onAppear {
            isTextWrapped = true
        }
#endif
    }
    
    private var licenseTextViewContent: some View {
        ScrollView(isTextWrapped ? .vertical : [.vertical, .horizontal]) {
            VStack(alignment: .leading) {
                Text(licenseText)
                    .font(.body)
                    .monospaced()
                    .padding()
                    .fixedSize(horizontal: !isTextWrapped, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(macOS)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Spacer().frame(height: 60)
        }
#endif
    }
}
