import SwiftUI

struct MarqueeText: View {
    let text: String
    @State private var offset: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var needsScroll: Bool = false

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 200) {
                    Text(text)
                        .font(.caption)
                        .lineLimit(1)
                        .background(WidthReader(width: $textWidth))
                        .fixedSize()
                    Text(text)
                        .font(.caption)
                        .lineLimit(1)
                        .fixedSize()
                }
                .offset(x: needsScroll ? offset : 0)
            }
            .disabled(true)
            .onAppear {
                containerWidth = geo.size.width
                needsScroll = textWidth > containerWidth
                if needsScroll {
                    offset = 0
                    let distance = (textWidth + 200)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.linear(duration: Double(max(distance, 1)) / 60.0).repeatForever(autoreverses: false)) {
                            offset = -distance
                        }
                    }
                }
            }
            .onChange(of: text) { _, _ in
                needsScroll = textWidth > containerWidth
                offset = 0
                if needsScroll {
                    let distance = (textWidth + 200)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.linear(duration: Double(max(distance, 1)) / 60.0).repeatForever(autoreverses: false)) {
                            offset = -distance
                        }
                    }
                }
            }
        }
        .frame(height: 14)
        .clipped()
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
