import SwiftUI

struct LicenseTextView: View {
    let licenseText: String
    let licenseLink: String?
    let licenseTitle: String // 追加
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @State private var isTextWrapped: Bool = true

    var body: some View {
        #if os(macOS)
        licenseTextViewContent
            .frame(width: 700, height: 500)
            .frame(maxWidth: .infinity, maxHeight: .infinity) // ここに追加
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
                                openURL(url)
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
                            Button(action: { openURL(url) }) {
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
                .modifier(NavSubtitleIfAvailable(subtitle: Text(licenseTitle))) // ここに追加
        }
        .onAppear { // ここに onAppear を追加
            isTextWrapped = true
        }
        #endif
    }

    private var licenseTextViewContent: some View {
        ScrollView(isTextWrapped ? .vertical : [.vertical, .horizontal]) {
            VStack(alignment: .leading) { // VStack を追加
                Text(licenseText)
                    .font(.body)
                    .monospaced()
                    .padding()
                    .fixedSize(horizontal: !isTextWrapped, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading) // VStack に frame を追加
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // ScrollView に frame を追加
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Spacer().frame(height: 60)
        }
    }
}
