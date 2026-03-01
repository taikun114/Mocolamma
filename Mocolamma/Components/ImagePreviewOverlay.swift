import SwiftUI

#if os(iOS)
import UIKit

/// iPadOSなどでマウスホイールやトラックパッドのスクロールをキャプチャするためのView
struct ScrollWheelView: UIViewRepresentable {
    var onScroll: (CGSize) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        // マウスホイールやトラックパッドのスクロールを許可
        pan.allowedScrollTypesMask = .continuous
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    class Coordinator: NSObject {
        var onScroll: (CGSize) -> Void
        init(onScroll: @escaping (CGSize) -> Void) {
            self.onScroll = onScroll
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            // スクロール量を抽出
            let translation = gesture.translation(in: gesture.view)
            if translation != .zero {
                onScroll(CGSize(width: translation.x, height: translation.y))
                // 累積しないようにリセット
                gesture.setTranslation(.zero, in: gesture.view)
            }
        }
    }
}
#endif

struct ImagePreviewOverlay: View {
    let image: PlatformImage
    let onClose: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @GestureState private var magnifyBy = CGFloat(1.0)
    
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    @State private var eventMonitor: Any?
    @State private var isRightMouseDown = false
    
    var body: some View {
        ZStack {
            // 背景（クリックで閉じる）
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    onClose()
                }
            
            // iPad/iOS用のスクロールキャプチャView（透明）
            #if os(iOS)
            ScrollWheelView { delta in
                // スクロールで移動
                withAnimation(.interactiveSpring()) {
                    offset.width += delta.width
                    offset.height += delta.height
                    lastOffset = offset
                }
            }
            .edgesIgnoringSafeArea(.all)
            #endif
            
            // 拡大画像
            Image(platformImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale * magnifyBy)
                .offset(offset)
                .simultaneousGesture(
                    MagnificationGesture()
                        .updating($magnifyBy) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            scale *= value
                            limitScale()
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            // 左ドラッグでも移動可能にする（標準的な挙動）
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if scale > 1.0 {
                            resetZoom()
                        } else {
                            scale = 2.0
                        }
                    }
                }
                .onTapGesture(count: 1) {
                    onClose()
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .previewZoomIn)) { _ in
            zoomIn()
        }
        .onReceive(NotificationCenter.default.publisher(for: .previewZoomOut)) { _ in
            zoomOut()
        }
        .onReceive(NotificationCenter.default.publisher(for: .previewActualSize)) { _ in
            resetZoom()
        }
        .onAppear {
            setupEventMonitor()
        }
        .onDisappear {
            removeEventMonitor()
        }
        #if !os(macOS)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        #endif
        .transition(.opacity.combined(with: .scale(0.9)))
    }
    
    private func setupEventMonitor() {
        #if os(macOS)
        let eventMask: NSEvent.EventTypeMask = [
            .keyDown, .scrollWheel, .rightMouseDown, .rightMouseUp, .rightMouseDragged
        ]
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { event in
            switch event.type {
            case .keyDown:
                return handleKeyDown(event)
            case .scrollWheel:
                handleScrollWheel(event)
                return nil
            case .rightMouseDown:
                isRightMouseDown = true
                return event
            case .rightMouseUp:
                isRightMouseDown = false
                lastOffset = offset // ズーム後の位置を保持
                return event
            case .rightMouseDragged:
                if isRightMouseDown {
                    handleRightMouseDrag(event)
                    return nil
                }
                return event
            default:
                return event
            }
        }
        #endif
    }
    
    private func removeEventMonitor() {
        #if os(macOS)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        #endif
    }
    
    #if os(macOS)
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { // Escape
            onClose()
            return nil
        }
        
        // Commandキーが押されている場合
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "+", "=":
                zoomIn()
                return nil
            case "-":
                zoomOut()
                return nil
            case "0":
                resetZoom()
                return nil
            default:
                break
            }
        }
        return event
    }
    
    private func handleScrollWheel(_ event: NSEvent) {
        // スクロールで移動
        withAnimation(.interactiveSpring()) {
            offset.width += event.scrollingDeltaX
            offset.height += event.scrollingDeltaY
            lastOffset = offset
        }
    }
    
    private func handleRightMouseDrag(_ event: NSEvent) {
        // 右ドラッグでズーム (上にドラッグで拡大、下にドラッグで縮小)
        let delta = event.deltaY
        if delta != 0 {
            let zoomFactor: CGFloat = 0.02
            // マウスのdeltaYは下方向が正なので、マイナスを掛けて上に移動したときに拡大するようにする
            let newScale = scale * (1.0 - delta * zoomFactor)
            withAnimation(.interactiveSpring()) {
                scale = max(1.0, min(20.0, newScale))
                if scale == 1.0 {
                    offset = .zero
                    lastOffset = .zero
                }
            }
        }
    }
    #endif
    
    private func zoomIn() {
        withAnimation(.spring()) {
            scale *= 1.2
            limitScale()
        }
    }
    
    private func zoomOut() {
        withAnimation(.spring()) {
            scale *= 0.8
            limitScale()
        }
    }
    
    private func resetZoom() {
        withAnimation(.spring()) {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
    
    private func limitScale() {
        if scale < 1.0 {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
        } else if scale > 20.0 {
            scale = 20.0
        }
    }
}
