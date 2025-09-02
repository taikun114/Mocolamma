import SwiftUI

struct MarqueeText: View {
    let text: String
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var needsScroll: Bool = false
    @State private var isFirstLoop: Bool = true // Track if it's the first loop

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
                isFirstLoop = true // Reset to first loop on text change
                startScrolling()
            }
        }
        .frame(height: 14)
        .clipped()
    }

    private func startScrolling() {
        needsScroll = textWidth > containerWidth
        if needsScroll {
            offset = isFirstLoop ? 0 : containerWidth // Start from left for first loop, right for subsequent
            let distance = textWidth + containerWidth + 200 // Distance to scroll
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { // 3 seconds delay
                withAnimation(.linear(duration: Double(distance) / 60.0)) {
                    offset = -textWidth - 200 // End position
                }
                // Schedule the next loop after the animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(distance) / 60.0) {
                    resetAndScroll()
                }
            }
        }
    }

    private func resetAndScroll() {
        isFirstLoop = false // Set to false for subsequent loops
        offset = containerWidth // Reset to start position (right edge)
        let distance = textWidth + containerWidth + 200 // Distance to scroll
        withAnimation(.linear(duration: Double(distance) / 60.0)) {
            offset = -textWidth - 200 // End position
        }
        // Schedule the next loop after the animation completes
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
