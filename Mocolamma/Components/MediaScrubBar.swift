import SwiftUI

struct MediaScrubBar: View {
    let position: TimeInterval
    let duration: TimeInterval
    let onScrubBegan: () -> Void
    let onScrubChanged: (TimeInterval) -> Void
    let onScrubEnded: (TimeInterval) -> Void
    let onScrubCancelled: () -> Void
    let onSeek: (TimeInterval) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isScrubbing = false
    @State private var scrubPosition: TimeInterval = 0
    @State private var scrubDuration: TimeInterval = 0
    @State private var scrubOrigin: TimeInterval = 0
    @GestureState private var isTouching = false

    private var displayedDuration: TimeInterval { isScrubbing ? scrubDuration : duration }
    private var displayedPosition: TimeInterval { isScrubbing ? scrubPosition : position }

    var body: some View {
        GeometryReader { geometry in
            let progress = displayedDuration > 0 ? min(1, max(0, displayedPosition / displayedDuration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * progress)
            }
            .frame(height: isScrubbing ? 8 : 4)
            .frame(maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle().inset(by: -6))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isScrubbing)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isTouching) { _, touching, _ in touching = true }
                    .onChanged { value in
                        guard duration > 0 else { return }
                        if !isScrubbing {
                            scrubDuration = duration
                            scrubOrigin = position
                            isScrubbing = true
                            onScrubBegan()
                        }
                        scrubPosition = time(translation: value.translation.width, width: geometry.size.width)
                        onScrubChanged(scrubPosition)
                    }
                    .onEnded { value in
                        guard isScrubbing else { return }
                        let position = time(translation: value.translation.width, width: geometry.size.width)
                        isScrubbing = false
                        if abs(value.translation.width) >= 1 {
                            onScrubEnded(position)
                        } else {
                            onScrubCancelled()
                        }
                    }
            )
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback Position")
        .accessibilityValue(Text("\(format(position)) of \(format(duration))"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(duration, position + 5))
            case .decrement: onSeek(max(0, position - 5))
            @unknown default: break
            }
        }
        .help("Drag to change the playback position.")
#if os(macOS)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { onSeek(max(0, position - 5)); return .handled }
        .onKeyPress(.rightArrow) { onSeek(min(duration, position + 5)); return .handled }
#endif
        .onChange(of: isTouching) { _, touching in
            // 中断時にはプレビューだけを解除し、再生位置は変更しない。
            if !touching && isScrubbing {
                isScrubbing = false
                onScrubCancelled()
            }
        }
    }

    private func time(translation: CGFloat, width: CGFloat) -> TimeInterval {
        MediaScrubPosition.relative(origin: scrubOrigin, translation: translation, width: width, duration: scrubDuration)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let seconds = max(0, Int(seconds))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

enum MediaScrubPosition {
    static func relative(origin: TimeInterval, translation: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0 else { return min(duration, max(0, origin)) }
        return min(duration, max(0, origin + Double(translation / width) * duration))
    }
}
