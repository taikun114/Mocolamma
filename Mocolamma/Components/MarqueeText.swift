import SwiftUI

struct MarqueeText: View {
    let text: String
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var needsScroll: Bool = false
    @State private var scrollTask: Task<Void, Never>? = nil
    
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
                restartScrolling()
            }
            .onChange(of: text) { _, _ in
                restartScrolling()
            }
            .onChange(of: textWidth) { _, _ in
                restartScrolling()
            }
            .onChange(of: containerWidth) { _, _ in
                restartScrolling()
            }
            .onDisappear {
                scrollTask?.cancel()
                scrollTask = nil
            }
        }
        .frame(height: 14)
        .clipped()
    }
    
    private func restartScrolling() {
        scrollTask?.cancel()
        needsScroll = textWidth > containerWidth && containerWidth > 0
        guard needsScroll else {
            offset = 0
            return
        }
        
        scrollTask = Task { @MainActor in
            // 初回表示：3秒待機後に左端からスクロール開始
            offset = 0
            let distance = textWidth + containerWidth + 200
            let duration = Double(distance) / 60.0
            
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            
            withAnimation(.linear(duration: duration)) {
                offset = -textWidth - 200
            }
            
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            
            // 2回目以降のループ（右端からスクロール）
            while !Task.isCancelled {
                offset = containerWidth
                withAnimation(.linear(duration: duration)) {
                    offset = -textWidth - 200
                }
                try? await Task.sleep(for: .seconds(duration))
            }
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
