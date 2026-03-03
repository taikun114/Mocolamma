import SwiftUI

struct NavSubtitleIfAvailable: ViewModifier {
    let subtitle: Text
    func body(content: Content) -> some View {
#if os(macOS) || os(iOS)
        if #available(iOS 26, macOS 11, *) {
            return AnyView(content.navigationSubtitle(subtitle))
        }
#endif
        return AnyView(content)
    }
}
