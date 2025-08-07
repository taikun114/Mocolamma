import SwiftUI


struct LicenseTextView: View {
    let licenseText: String
    let licenseLink: String? // 新しく追加
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading) {
                    Text("License")
                        .font(.title)
                        .fontWeight(.bold)
                        .padding()

                    Text(licenseText)
                        .font(.body)
                        .monospaced()
                        .padding()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 20) // スクロールビューのコンテンツが下部のオーバーレイに隠れないように
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Spacer().frame(height: 60)
            }
        }
        #if os(macOS)
        .frame(width: 700, height: 500)
        #endif
        #if os(macOS)
        .background(Color(nsColor: .controlBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif // モーダル全体の背景色
        .overlay(alignment: .bottom) { // 下部にオーバーレイとしてVisualEffectViewとボタンを配置
            ZStack(alignment: .center) {
                // macOS 26以降であればglassEffect、それ以外はVisualEffectView
                if #available(iOS 26, macOS 26, *) {
                    Color.clear
                        .glassEffect() // HistoryWindowViewに合わせたcornerRadius
                        .edgesIgnoringSafeArea(.horizontal)
                } else {
                    #if os(macOS)
                    VisualEffectView(material: .headerView, blendingMode: .withinWindow)
                        .edgesIgnoringSafeArea(.horizontal)
                    #else
                    VisualEffectView(material: .systemThinMaterial)
                        .edgesIgnoringSafeArea(.horizontal)
                    #endif
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
    }
}
