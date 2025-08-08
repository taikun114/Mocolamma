import SwiftUI

struct LicenseTextView: View {
    let licenseText: String
    let licenseLink: String? // 新しく追加
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    var body: some View {
        #if os(macOS)
        licenseTextViewContent
            .frame(width: 700, height: 500)
            .overlay(alignment: .bottom) { // 下部にオーバーレイとしてVisualEffectViewとボタンを配置
                ZStack(alignment: .center) {
                    VisualEffectView(material: .headerView, blendingMode: .withinWindow)
                        .edgesIgnoringSafeArea(.horizontal)
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
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if let link = licenseLink, let url = URL(string: link) {
                            Button(action: { openURL(url) }) {
                                Image(systemName: "paperclip")
                            }
                        }
                    }
                }
        }
        #endif
    }

    private var licenseTextViewContent: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text(licenseText)
                    .font(.body)
                    .monospaced()
                    .padding()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}