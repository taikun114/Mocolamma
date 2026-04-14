import SwiftUI

struct LicenseTextView: View {
    let licenseText: String
    let licenseLink: String?
    let licenseTitle: String
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @State private var isTextWrapped: Bool = true
    @State private var showingLicenseLinkAlert = false
    
    private var isOS26OrLater: Bool {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            return true
        } else {
            return false
        }
    }
    
    // スクロール軸の決定
    private var scrollAxes: Axis.Set {
#if os(visionOS)
        return .vertical
#else
        return isTextWrapped ? .vertical : [.vertical, .horizontal]
#endif
    }
    
    // 水平方向の固定解除（折り返し）の決定
    private var horizontalFixed: Bool {
#if os(visionOS)
        return false
#else
        return !isTextWrapped
#endif
    }
    
    var body: some View {
#if os(macOS)
        ScrollView(scrollAxes) {
            licenseTextViewContent
        }
        .frame(width: 700, height: 500)
        .safeAreaInset(edge: .bottom, spacing: 0) { // 下部にセーフエリアインセットとしてVisualEffectViewとボタンを配置
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
                        if let link = licenseLink, let _ = URL(string: link) {
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
#if os(visionOS)
                        .tint(.accentColor)
                        .foregroundStyle(.white)
#endif
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
                .frame(height: 60) // インセットの固定高さ
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
        NavigationStack {
            licenseScrollView
                .navigationTitle("License")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if let link = licenseLink, let _ = URL(string: link) {
                            Button(action: { showingLicenseLinkAlert = true }) {
                                Image(systemName: "paperclip")
                            }
                        }
                    }
                    
#if os(iOS)
                    // iOS 26.0 以降の場合のみ ToolbarSpacer を追加
                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .primaryAction)
                    }
#endif

#if !os(visionOS)
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            isTextWrapped.toggle()
                            print("isTextWrapped: \(isTextWrapped)")
                        }) {
                            Label("Toggle Text Wrapping", systemImage: "arrow.up.and.down.text.horizontal")
                        }
                    }
#endif
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
#if os(visionOS)
        .frame(width: 800, height: 600)
#endif
        .onAppear {
            isTextWrapped = true
        }
        .presentationBackground(Color(uiColor: .systemBackground))
#endif
    }
    
    @ViewBuilder
    private var licenseScrollView: some View {
        let scrollView = ScrollView(scrollAxes) {
            licenseTextViewContent
        }
        
#if os(visionOS)
        if #available(visionOS 26.0, *) {
            scrollView
                .scrollInputBehavior(.enabled, for: .look)
        } else {
            scrollView
        }
#else
        scrollView
#endif
    }
    
    private var licenseTextViewContent: some View {
        VStack(alignment: .leading) {
            Text(licenseText)
                .font(.callout.monospaced())
                .padding()
                .fixedSize(horizontal: horizontalFixed, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
