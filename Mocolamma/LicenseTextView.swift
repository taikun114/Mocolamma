import SwiftUI

// VisualEffectViewの定義を追加
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct LicenseTextView: View {
    let licenseText: String
    let licenseLink: String? // 新しく追加
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading) {
                    HStack {
                        Text("License") // タイトル
                            .font(.title)
                            .fontWeight(.bold)
                            .padding(.vertical, 10) // 上下に10ポイントのパディングを追加
                            .padding(.horizontal)

                        Spacer()

                        if let link = licenseLink, let url = URL(string: link) {
                            Button("Open License Page") {
                                openURL(url)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.horizontal)
                        }
                    }

                    Text(licenseText)
                        .font(.body)
                        .monospaced()
                        .padding(.horizontal)
                        .padding(.vertical, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 20) // スクロールビューのコンテンツが下部のオーバーレイに隠れないように
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Spacer().frame(height: 60)
            }
        }
        .frame(width: 700, height: 500) // シートの固定サイズを設定
        .background(Color(.controlBackgroundColor)) // モーダル全体の背景色
        .overlay(alignment: .bottom) { // 下部にオーバーレイとしてVisualEffectViewとボタンを配置
            ZStack(alignment: .center) {
                // macOS 26以降であればglassEffect、それ以外はVisualEffectView
                if #available(macOS 26, *) {
                    Color.clear
                        .glassEffect() // HistoryWindowViewに合わせたcornerRadius
                        .edgesIgnoringSafeArea(.horizontal)
                } else {
                    VisualEffectView(material: .headerView, blendingMode: .withinWindow)
                        .edgesIgnoringSafeArea(.horizontal) // 水平方向いっぱいに広がるようにする
                }


                HStack {
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
