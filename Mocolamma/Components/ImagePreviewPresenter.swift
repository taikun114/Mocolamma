import SwiftUI

@Observable
final class ImagePreviewPresentation {
    var image: PlatformImage?
}

private struct ImagePreviewPresentationKey: EnvironmentKey {
    static let defaultValue: ImagePreviewPresentation? = nil
}

extension EnvironmentValues {
    var imagePreviewPresentation: ImagePreviewPresentation? {
        get { self[ImagePreviewPresentationKey.self] }
        set { self[ImagePreviewPresentationKey.self] = newValue }
    }
}

private struct FocusedImagePreviewKey: FocusedValueKey {
    typealias Value = ImagePreviewPresentation
}

extension FocusedValues {
    var imagePreviewPresentation: ImagePreviewPresentation? {
        get { self[FocusedImagePreviewKey.self] }
        set { self[FocusedImagePreviewKey.self] = newValue }
    }
}

/// 画像の表示状態と表示先を画面ごとに保持し、別のタブへ持ち越さないようにします。
struct ImagePreviewPresenter: ViewModifier {
    var bottomInset: CGFloat = 0
    @State private var presentation = ImagePreviewPresentation()

    func body(content: Content) -> some View {
        content
            .environment(\.imagePreviewPresentation, presentation)
            .overlay {
                if let image = presentation.image {
                    ImagePreviewOverlay(image: image, onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            presentation.image = nil
                        }
                    }, bottomInset: bottomInset)
                    .zIndex(100)
                }
            }
            .focusedSceneValue(\.imagePreviewPresentation, presentation)
            .onDisappear { presentation.image = nil }
    }
}
