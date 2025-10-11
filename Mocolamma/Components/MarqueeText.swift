import SwiftUI

struct MarqueeText: View {
    let text: String
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var needsScroll: Bool = false
    @State private var isFirstLoop: Bool = true // 最初のループかどうかを追跡

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.caption)
                    .lineLimit(1)
                    .background(WidthReader(width: $textWidth))
                    .fixedSize()
                    .offset(x: needsScroll ? offset : 0)
            }
            .disabled(true)
            .onAppear {
                containerWidth = geo.size.width
                startScrolling()
            }
            .onChange(of: text) { _, _ in
                isFirstLoop = true // テキスト変更時に最初のループにリセット
                startScrolling()
            }
        }
        .frame(height: 14)
        .clipped()
    }

    private func startScrolling() {
        needsScroll = textWidth > containerWidth
        if needsScroll {
            offset = isFirstLoop ? 0 : containerWidth // 最初のループは左端から、以降は右端から開始
            let distance = textWidth + containerWidth + 200 // スクロール距離
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { // 3秒の遅延
                withAnimation(.linear(duration: Double(distance) / 60.0)) {
                    offset = -textWidth - 200 // 終了位置
                }
                // アニメーション完了後に次のループをスケジュール
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(distance) / 60.0) {
                    resetAndScroll()
                }
            }
        }
    }

    private func resetAndScroll() {
        isFirstLoop = false // 以降のループではfalseに設定
        offset = containerWidth // スタート位置にリセット（右端）
        let distance = textWidth + containerWidth + 200 // スクロール距離
        withAnimation(.linear(duration: Double(distance) / 60.0)) {
            offset = -textWidth - 200 // 終了位置
        }
        // アニメーション完了後に次のループをスケジュール
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(distance) / 60.0) {
            resetAndScroll()
        }
    }
}

private struct WidthReader: View {
    @Binding var width: CGFloat
    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { width = geo.size.width }
                .onChange(of: geo.size.width) { _, new in width = new }
        }
    }
}
