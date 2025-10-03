import SwiftUI

struct NavSubtitleIfAvailable: ViewModifier {
    let subtitle: Text
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            return AnyView(content.navigationSubtitle(subtitle))
        } else {
            return AnyView(content)
        }
        #elseif os(macOS)
        return AnyView(content.navigationSubtitle(subtitle))
        #else
        return AnyView(content)
        #endif
    }
}
