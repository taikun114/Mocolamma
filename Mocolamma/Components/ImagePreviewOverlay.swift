import SwiftUI

#if os(iOS)
import UIKit

/// iOS/iPadOSのすべてのジェスチャーを統合管理するView
struct GestureCaptureView: UIViewRepresentable {
    var onScroll: (CGSize) -> Void
    var onZoom: (CGFloat, CGPoint) -> Void
    var onPinch: (CGFloat, CGPoint) -> Void
    var onTap: () -> Void
    var onDoubleTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.allowedScrollTypesMask = .continuous
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        view.addGestureRecognizer(doubleTap)
        
        tap.require(toFail: doubleTap)
        
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.allowableMovement = 30
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)
        
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: GestureCaptureView
        var isZoomMode = false
        var zoomAnchor: CGPoint = .zero
        var lastLocation: CGPoint = .zero
        
        init(parent: GestureCaptureView) {
            self.parent = parent
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let location = gesture.location(in: gesture.view)
            
            if isZoomMode {
                if gesture.state == .changed {
                    let deltaY = location.y - lastLocation.y
                    parent.onZoom(-deltaY * 0.01, zoomAnchor)
                }
                lastLocation = location
            } else {
                if translation != .zero {
                    parent.onScroll(CGSize(width: translation.x, height: translation.y))
                    gesture.setTranslation(.zero, in: gesture.view)
                }
            }
            
            if gesture.state == .ended || gesture.state == .cancelled {
                isZoomMode = false
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .changed {
                parent.onPinch(gesture.scale, gesture.location(in: gesture.view))
                gesture.scale = 1.0
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            parent.onTap()
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            parent.onDoubleTap(gesture.location(in: gesture.view))
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began {
                isZoomMode = true
                zoomAnchor = gesture.location(in: gesture.view)
                lastLocation = zoomAnchor
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
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
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景
                Color.black.opacity(0.8)
                    .contentShape(Rectangle())
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        onClose()
                    }
                
                // iPad/iOS用のジェスチャーキャプチャView
                #if os(iOS)
                GestureCaptureView(
                    onScroll: { delta in
                        withAnimation(.interactiveSpring()) {
                            offset.width += delta.width
                            offset.height += delta.height
                            lastOffset = offset
                        }
                    },
                    onZoom: { factor, anchor in
                        updateScale(newScale: scale * (1.0 + factor), anchor: anchor, in: geometry.size)
                    },
                    onPinch: { pinchScale, anchor in
                        updateScale(newScale: scale * pinchScale, anchor: anchor, in: geometry.size)
                    },
                    onTap: {
                        onClose()
                    },
                    onDoubleTap: { anchor in
                        withAnimation(.spring()) {
                            if scale > 1.0 {
                                resetZoom()
                            } else {
                                updateScale(newScale: 2.0, anchor: anchor, in: geometry.size)
                            }
                        }
                    }
                )
                .edgesIgnoringSafeArea(.all)
                .zIndex(10)
                #endif
                
                // 拡大画像
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale * magnifyBy)
                    .offset(offset)
                    #if os(macOS)
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
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    // macOSでのダブルタップ・シングルタップ操作をSwiftUI標準に戻す
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
                    #endif
            }
            .onAppear { setupEventMonitor() }
            .onDisappear { removeEventMonitor() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .previewZoomIn)) { _ in zoomIn() }
        .onReceive(NotificationCenter.default.publisher(for: .previewZoomOut)) { _ in zoomOut() }
        .onReceive(NotificationCenter.default.publisher(for: .previewActualSize)) { _ in resetZoom() }
        #if !os(macOS)
        .onKeyPress(.escape) { onClose(); return .handled }
        #endif
        .transition(.opacity.combined(with: .scale(0.9)))
    }
    
    /// 特定のアンカー（指やカーソルの位置）を維持しながらスケールを更新する
    private func updateScale(newScale: CGFloat, anchor: CGPoint, in size: CGSize) {
        let limitedScale = max(1.0, min(20.0, newScale))
        if limitedScale == scale { return }
        
        let zoomRatio = limitedScale / scale
        let centerX = size.width / 2
        let centerY = size.height / 2
        
        let relativeAnchorX = anchor.x - centerX - offset.width
        let relativeAnchorY = anchor.y - centerY - offset.height
        
        let newOffsetX = offset.width - (relativeAnchorX * (zoomRatio - 1))
        let newOffsetY = offset.height - (relativeAnchorY * (zoomRatio - 1))
        
        if limitedScale == 1.0 {
            resetZoom()
        } else {
            scale = limitedScale
            offset = CGSize(width: newOffsetX, height: newOffsetY)
            lastOffset = offset
        }
    }
    
    private func setupEventMonitor() {
        #if os(macOS)
        let eventMask: NSEvent.EventTypeMask = [
            .keyDown, .scrollWheel, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .leftMouseDragged
        ]
        
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { event in
            switch event.type {
            case .keyDown:
                return handleKeyDown(event)
            case .scrollWheel:
                handleScrollWheel(event)
                return nil
                
            case .rightMouseDown:
                return nil
                
            case .rightMouseDragged:
                let delta = event.deltaY
                if delta != 0 {
                    let newScale = scale * (1.0 - delta * 0.02)
                    withAnimation(.interactiveSpring()) {
                        scale = max(1.0, min(20.0, newScale))
                        if scale == 1.0 {
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
                }
                return nil
                
            case .rightMouseUp:
                lastOffset = offset
                return nil
                
            case .leftMouseDragged:
                if event.modifierFlags.contains(.control) {
                    let delta = event.deltaY
                    if delta != 0 {
                        let newScale = scale * (1.0 - delta * 0.02)
                        withAnimation(.interactiveSpring()) {
                            scale = max(1.0, min(20.0, newScale))
                            if scale == 1.0 {
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
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
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor); eventMonitor = nil }
        #endif
    }
    
    #if os(macOS)
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { onClose(); return nil }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "+", "=": zoomIn(); return nil
            case "-": zoomOut(); return nil
            case "0": resetZoom(); return nil
            default: break
            }
        }
        return event
    }
    
    private func handleScrollWheel(_ event: NSEvent) {
        withAnimation(.interactiveSpring()) {
            offset.width += event.scrollingDeltaX
            offset.height += event.scrollingDeltaY
            lastOffset = offset
        }
    }
    #endif
    
    private func zoomIn() { withAnimation(.spring()) { scale *= 1.2; limitScale() } }
    private func zoomOut() { withAnimation(.spring()) { scale *= 0.8; limitScale() } }
    private func resetZoom() {
        withAnimation(.spring()) {
            scale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
    private func limitScale() {
        if scale < 1.0 { scale = 1.0; offset = .zero; lastOffset = .zero }
        else if scale > 20.0 { scale = 20.0 }
    }
}
