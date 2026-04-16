import SwiftUI

struct NavSubtitleIfAvailable: ViewModifier {
    let subtitle: Text
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS) || os(iOS)
        if #available(iOS 26, macOS 11, *) {
            content.navigationSubtitle(subtitle)
        } else {
            content
        }
#else
        content
#endif
    }
}
