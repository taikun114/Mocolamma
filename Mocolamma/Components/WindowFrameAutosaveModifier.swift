import SwiftUI

#if os(macOS)
import AppKit

private final class WindowFrameObserver {
    let key: String
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var hasRestored = false
    
    init(name: String) {
        self.key = "Mocolamma_WindowFrame_\(name)"
    }
    
    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        cleanup()
        
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak self] _ in
            self?.saveFrame()
        })
        observers.append(nc.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            self?.saveFrame()
        })
        observers.append(nc.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
            self?.saveFrame()
        })
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.saveFrame()
        })
        
        restoreFrame(for: window)
    }
    
    private func restoreFrame(for window: NSWindow) {
        guard !hasRestored else { return }
        hasRestored = true
        
        guard let frameString = UserDefaults.standard.string(forKey: key) else { return }
        let savedRect = NSRectFromString(frameString)
        // 最小サイズ制約（1000x500）以上の有効な矩形であるか確認
        guard savedRect.width >= 100, savedRect.height >= 100 else { return }
        
        DispatchQueue.main.async {
            // フルスクリーンでないことを確認
            guard !window.styleMask.contains(.fullScreen) else { return }
            
            // ディスプレイ領域内にあるか確認し、画面外なら画面内に収める
            let screens = NSScreen.screens
            let isVisibleOnAnyScreen = screens.contains { screen in
                NSIntersectsRect(screen.visibleFrame, savedRect)
            }
            
            if isVisibleOnAnyScreen {
                window.setFrame(savedRect, display: true, animate: false)
            } else if let mainScreen = NSScreen.main {
                var adjustedRect = savedRect
                adjustedRect.origin.x = max(mainScreen.visibleFrame.minX, min(savedRect.origin.x, mainScreen.visibleFrame.maxX - savedRect.width))
                adjustedRect.origin.y = max(mainScreen.visibleFrame.minY, min(savedRect.origin.y, mainScreen.visibleFrame.maxY - savedRect.height))
                window.setFrame(adjustedRect, display: true, animate: false)
            }
            #if DEBUG
            print("DEBUG: Window frame restored from UserDefaults: \(savedRect)")
            #endif
        }
    }
    
    private func saveFrame() {
        guard let window = window else { return }
        guard !window.styleMask.contains(.fullScreen), !window.isMiniaturized else { return }
        let frameString = NSStringFromRect(window.frame)
        UserDefaults.standard.set(frameString, forKey: key)
        #if DEBUG
        print("DEBUG: Window frame saved to UserDefaults: \(frameString)")
        #endif
    }
    
    private func cleanup() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }
    
    deinit {
        cleanup()
    }
}

private final class WindowFrameAutosaveNSView: NSView {
    private let observer: WindowFrameObserver
    
    init(autosaveName: String) {
        self.observer = WindowFrameObserver(name: autosaveName)
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = self.window {
            observer.attach(to: window)
        }
    }
}

private struct WindowFrameAutosaveAccessor: NSViewRepresentable {
    let autosaveName: String
    
    func makeNSView(context: Context) -> NSView {
        WindowFrameAutosaveNSView(autosaveName: autosaveName)
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// macOS環境において、ウィンドウのフレーム（サイズ・位置）をUserDefaultsに明示的に保存・復元します。
    @ViewBuilder
    func windowFrameAutosaveName(_ name: String) -> some View {
        self.background(WindowFrameAutosaveAccessor(autosaveName: name))
    }
}
#else
extension View {
    @ViewBuilder
    func windowFrameAutosaveName(_ name: String) -> some View {
        self
    }
}
#endif
